# All-In: implementation plan

Status: plan for v1 and later. It implements the 15 approved wireframe screens (`design/wireframes/index.html`), reskinned as cozy high fantasy, plus a new Play section ("The Arena"). Code is written milestone by milestone by Sonnet subagents and checked by Haiku subagents, so every task below names the files it owns and how to test it.

---

## 0. Ground rules

- **Teach thinking, not charts.** The app never asks the user to recall an answer it has stored. Every correct answer is computed by the engine for a freshly generated spot.
- **Poker words stay real.** The fantasy skin changes art, names and voice only. *Pot, blinds, BB, c-bet, range, equity* keep their real names, so the skills carry over to real poker.
- **Grade decisions, not results.** Every score comes from EV. Luck is always shown as its own number.
- **Every opponent is a white box.** All bots expose their full strategy as a probability distribution. The grader, range tracker and coach can read it exactly. This is what makes EV grading accurate offline without an LLM.
- **Deterministic by default.** All randomness flows from an explicit seeded RNG. Any hand, spot or simulation can be replayed from its seed and action log.
- **Offline and App Store-ready from day one.** Sandbox on, no network entitlement, privacy manifest, no accounts.

### Environment and conventions (taken from the owner's Kata repo)

| Item | Choice |
|---|---|
| Toolchain | Xcode 27.2, Swift 6.4.2, Swift 6 language mode, strict concurrency |
| Platform | macOS 26.0 deployment target, Apple Silicon only (arm64) |
| Project | Hand-written `AllIn.xcodeproj` (objectVersion 77, `PBXFileSystemSynchronizedRootGroup`), copying the structure of Kata's `KataMac` target. No xcodegen or tuist (neither is installed). |
| Logic | One local package `Packages/AllInKit` (swift-tools 6.2) holds all logic, with Swift Testing |
| Bundle id / team | `com.github.meysampg.allin`, team `N9GSW3M5U8` (same as Kata) |
| Reuse | Port `KataSRS` (FSRS-5 scheduler, `DayKey`, `StreakCalculator` and their tests) from `../Kata/Packages/KataKit/Sources/KataSRS/` |
| Formatting | `xcrun swift-format` (comes with the toolchain), with config in `.swift-format` |
| CI | None. Local scripts in `Tools/` are the only gate. |

---

## 1. Architecture

### 1.1 Repository layout

```
allin/
├─ AllIn.xcodeproj
├─ Config/Info.plist
├─ AllIn/                         app target (SwiftUI shell, features, wiring)
│  ├─ App/        AllInApp, AppModel, AppRouter, Screen, RootView, Commands, DebugLaunch, AppSettings
│  ├─ Features/   Menu/ Career/ Venue/ Lesson/ Table/ Review/ Boss/ Result/ Lobby/ Tournament/
│  │              Gym/ Rivals/ MyGame/ Settings/ Arena/ Coach/
│  ├─ Resources/  Assets.xcassets, PrivacyInfo.xcprivacy, AllIn.entitlements
│  └─ (folder refs copied into the bundle) ../Content, ../Themes
├─ AllInUITests/                  XCUITest smoke tests (one per screen)
├─ Packages/AllInKit/
│  ├─ Package.swift
│  ├─ Sources/
│  │  ├─ PokerCore/          cards, evaluator, rules, reducer, events, strategy protocol
│  │  ├─ PokerEquity/        ranges, equity engine, board analysis, preflop table
│  │  ├─ PokerHost/          Seat protocol, GameHost actor, cash/tournament sessions
│  │  ├─ PokerAI/            personality bots, baseline, range tracker, player model, exploit, (later) blueprint, resolver, advisor
│  │  ├─ PokerAnalysis/      EV estimator, decision grader, luck, leaks, stats
│  │  ├─ Curriculum/         content model, loader, spot generator, answer evaluation, skills, SRS, coach logic
│  │  ├─ ThemeKit/           theme manifest, slots, resolver, validator
│  │  ├─ TableKit/           SpriteKit table scene, code-drawn renderers, animation queue
│  │  ├─ AllInUI/            SwiftUI design system and shared poker views
│  │  ├─ AllInStore/         SwiftData schema, ProgressStore, hand archive
│  │  ├─ PokerAbstraction/   (M10) hand isomorphism, buckets, action abstraction, blueprint format
│  │  ├─ Solver/             (M10) CFR/MCCFR library
│  │  ├─ allin-tool/         CLI: content, theme, sim, gen-preflop, hh
│  │  └─ allin-solve/        (M10) CLI: train, evaluate and export blueprints
│  └─ Tests/  <Module>Tests, ContentTests, HeavyTests (release-only)
├─ Content/                       curriculum and characters as JSON (authoring source = shipped data)
├─ Themes/hearthwood.allintheme/  default theme pack (mostly procedural slots)
├─ Tools/   build.sh test.sh run.sh screens.sh make_app_icon.swift
└─ docs/    PLAN.md ARCHITECTURE.md CONTENT_GUIDE.md THEME_GUIDE.md
```

### 1.2 Modules and boundaries

```
PokerCore ──► PokerEquity ──► PokerAI ──► PokerAnalysis ──► Curriculum ──► AllInStore
    │                            ▲
    └──► PokerHost ──────────────┘ (tests and the CLI only; PokerAI does not import PokerHost)
ThemeKit ──► TableKit (SpriteKit, + PokerCore)
ThemeKit ──► AllInUI  (SwiftUI, + PokerCore, PokerEquity)
App ──► everything
```

| Module | May import | Owns |
|---|---|---|
| PokerCore | Swift stdlib, Foundation | `Card`, `CardSet`, `Deck`, `SeededRNG`, `HandEvaluator`, `TableConfig`, `Action`, `LegalActions`, `HandState`, `HandReducer`, `PotCalculator`, `GameEvent`, `EventLog`, `HandReplayer`, `StrategyProvider`, `DecisionContext`, `ActionDistribution` |
| PokerEquity | PokerCore | `HandRange` (1326 weights), `HandClass` (169), range parser, `EquityCalculator`, `BoardAnalyzer` (texture, nuts, hands that beat you, draws/outs), `PreflopEquityTable` |
| PokerHost | PokerCore | `Seat`, `DecisionRequest`, `GameHost` (actor), `BotSeat`, `ScriptedSeat`, `RandomSeat`, `CashSession`, `TournamentDirector` (M9) |
| PokerAI | PokerCore, PokerEquity, PokerAbstraction (M10) | `PersonalityStrategy`, `BaselineStrategy`, `RangeTracker`, `PlayerModel`, `ExploitStrategy`, `BlueprintStrategy`, `RiverResolver`, `Advisor` |
| PokerAnalysis | PokerCore, PokerEquity, PokerAI | `ActionEVEstimator`, `ClosedFormEV`, `DecisionGrader`, `SessionScorer`, `LuckCalculator`, `LeakDetector`, `PlayerStats` |
| Curriculum | the four above | `ContentLibrary`, `SpotTemplate`, `SpotGenerator`, `SpotEvaluator`, `SkillModel`, FSRS, `DrillScheduler`, `CoachEngine`, `CharacterCatalog`, boss and exam rules |
| ThemeKit | Foundation, CoreGraphics, ImageIO, AVFoundation | `ThemeManifest`, `AssetSlot`, `ThemePack`, `ThemeResolver`, `ThemeValidator` |
| TableKit | SpriteKit, ThemeKit, PokerCore | `TableScene`, nodes, `CardRenderer`, `TableRenderer`, `ChipRenderer`, `AnimationQueue`, `SoundBank` |
| AllInUI | SwiftUI, Charts, ThemeKit, PokerCore, PokerEquity | design system, `CardView`, `RangeGridView`, `EquityBars`, `Meter`, `AvatarMedallion`, explainers |
| AllInStore | SwiftData, Curriculum, PokerAnalysis | `SchemaV1…`, `MigrationPlan`, `ProgressStore`, `HandArchive`, `SaveFile` |

**Hard rule:** the six engine modules (PokerCore through Curriculum, plus PokerAbstraction and Solver) never import SwiftUI, AppKit, SpriteKit or SwiftData. They must stay portable to a Linux server later. `Tools/test.sh lint` greps for violations.

### 1.3 Concurrency and determinism rules (copied into ARCHITECTURE.md)

- Engine types are `Sendable` value types. `HandReducer` is a pure function: `(HandState, Command) throws -> (HandState, [GameEvent])`.
- `GameHost` is an `actor`. UI controllers are `@MainActor @Observable final class`. SpriteKit scenes stay on the main actor.
- `StrategyProvider` is `Sendable` and stateless per call. Adaptive state (`PlayerModel`) is passed in as an immutable snapshot at the start of each hand.
- Randomness is always `inout some RandomNumberGenerator` with `SeededRNG` (xoshiro256**). Nothing calls `SystemRandomNumberGenerator` except seed creation in the app layer.
- AI, equity and grading never run on the main actor. The UI shows progressive results.

### 1.4 Rules engine (PokerCore)

- **Card encoding:** `Card` is a `UInt8` = `rank * 4 + suit` (0–51). `CardSet` is a `UInt64` bitmask, which makes dead-card removal and isomorphism checks cheap.
- **Game:** No-limit Texas Hold'em. Supports blinds, antes, big-blind ante (tournaments), the heads-up blind rule (button posts SB and acts first preflop), min-raise equal to the last full raise, an all-in short of a full raise not reopening action, uncalled bets returned, and all-in runout.
- **Button:** cash games use a simple moving button. Tournaments use the dead-button rule (M9).
- **Chips:** `Int` chips. Blinds are integers. The odd chip goes to the first winner left of the button.
- **Pots:** `PotCalculator` builds main and side pots from per-seat contributions (chips from folded players stay in as dead money). `PotDistributor` splits each pot among the best eligible hands.
- **Showdown order:** last aggressor shows first, otherwise first seat left of the button. Losing hands may muck (bots muck; the review can reveal them because the host knows every card).

### 1.5 Seat protocol and game host (event-sourced)

```swift
public protocol Seat: Sendable {
  var id: SeatID { get }
  func observe(_ event: LoggedEvent) async                    // already filtered for this seat
  func decide(_ request: DecisionRequest) async -> Action      // the host validates the answer
}

public struct LoggedEvent: Codable, Sendable {
  public let seq: Int; public let handID: HandID
  public let visibility: Visibility            // .public, .seat(SeatID), .hostOnly
  public let event: GameEvent
}

public enum GameEvent: Codable, Sendable {
  case handStarted(HandStart)                  // seats, stacks, button, blinds, deckCommitment (hash of the seed)
  case blindPosted(SeatID, BlindKind, Int)
  case holeCardsDealt(SeatID, [Card])          // visibility .seat(id)
  case actionRequested(SeatID, LegalActions, deadline: Duration?)
  case actionTaken(SeatID, Action, stackAfter: Int, potAfter: Int)
  case streetDealt(Street, [Card])
  case potsUpdated([Pot])
  case showdown([Reveal])
  case potAwarded(potIndex: Int, winners: [SeatID], amounts: [Int])
  case handEnded(HandSummary)                  // includes the seed reveal (verifies the commitment)
}
```

- The **host is authoritative.** Seats send only actions. The host checks the action against `LegalActions` and the expected `seq`. An illegal action becomes the closest legal one (check if possible, else fold), and the host logs a warning.
- The **event log is the hand history.** Replaying `[LoggedEvent]` through `HandReplayer` rebuilds every state exactly. The same log feeds review, the archive and the stats.
- **Seat implementations:** `LocalHumanSeat` (app layer, bridges to the UI with a continuation), `BotSeat(strategy:rng:thinkTime:)`, `ScriptedSeat` (tests and lessons), `RandomSeat`. A future `RemoteSeat` would wrap a transport. Because the host already filters events per seat and accepts only validated commands, a server could run `GameHost` unchanged.
- **UI stream:** the host also emits a spectator stream (public events plus the human's private events). The UI plays it back through an `AnimationQueue`. The host may run ahead of the animations. Action buttons appear only when the queue reaches the human's `actionRequested`.
- **Bot timing:** think time is applied by `BotSeat`, scaled by game speed (Relaxed 1.4×, Normal 1×, Turbo 0.3×), never below 120 ms. Compute time is hidden inside the think time.

### 1.6 Hand evaluator

- **Algorithm:** a 7-card perfect-hash evaluator in the style of HenryRLee's evaluator. The tables are **generated by our own code** at first use, not copied.
  - *Flush path:* per-suit counts; when one suit has 5 or more cards, its 13-bit rank mask indexes an 8192-entry flush table.
  - *Non-flush path:* rank counts are indexed through a precomputed combinatorial hash into a table of about 49k rank multisets.
- **Building the tables:** a slow, obviously-correct `NaiveEvaluator` (best 5 of 7 by brute force) fills them in under 100 ms. They are cached in memory. Nothing large ships in the bundle.
- **Output:** `HandValue` is a `UInt16` from 1 (best) to 7462, plus a `HandCategory` and a `bestFive(_:)` helper. The helper drives the gold "winning cards lift and glow" animation and the "Two Pair, Kings and Nines" text.
- **Target speed:** at least 30M evaluations per second on one core in release builds. The heavy test asserts at least 10M.

### 1.7 Equity engine (PokerEquity)

| Query | Method | Target time (M1 Pro, release) |
|---|---|---|
| Hand vs hand, preflop | lookup in the shipped `preflop169.bin` (generated by `allin-tool gen-preflop` by exact enumeration, about 120 KB), exact for the suit pattern | < 1 µs |
| Hand vs hand/range, flop or later | exact enumeration of the remaining boards × opponent combos, with card removal | < 5 ms |
| Range vs range, any street | Monte Carlo with the seeded RNG, parallel `TaskGroup` | 50k samples < 40 ms |
| Multiway (3–9 players) | Monte Carlo | 20k samples < 40 ms |
| Sandbox / live bars | `AsyncStream<EquityEstimate>` that refines in batches of 2k samples | first value < 16 ms |

`HandRange` holds 1326 `Float` weights. It converts to and from the 13×13 grid and a text format (`"22+, A2s+, KTo+, 76s:0.5"`). `BoardAnalyzer` returns the texture (paired, monotone, two-tone, rainbow, connected), the nut hand, the ordered list of hand classes that beat a given hand, made-hand class, draws and outs. Lessons, bots and the coach all share it.

### 1.8 EV, decision quality and luck (PokerAnalysis)

**Range inference.** `RangeTracker` starts each opponent at their preflop prior. At every action it multiplies each of the 1326 combos by `P(action | combo, context)` from that opponent's own `StrategyProvider`. Because every bot is a white box, this is exact Bayesian inference, not guessing.

**EV of each candidate action.** `ActionEVEstimator` works as follows:
1. Candidates are fold, check/call, and the bet sizes on the action bar (⅓, ½, ⅔, pot, all-in, clamped to legal sizes).
2. For each candidate, sample opponent hands from their tracked ranges.
3. Roll out the rest of the hand. Opponents use their real policies. The hero continues with `BaselineStrategy`.
4. Average the result in bb. Defaults: 4,000 rollouts per candidate, with common random numbers across candidates to reduce variance.
5. Grading runs in the background after each hand and never blocks play.

**Closed-form fast paths.** `ClosedFormEV` covers spots where rollouts are unnecessary: EV(call) = equity × (pot + call) − call when no further betting is possible, simple fold-equity bets, and push/fold. Lesson templates choose which method they use.

**Grading:**

```
evLoss  = EV(best) − EV(chosen)                        // in bb, ≥ 0
close   = EV(best) − EV(second) < max(0.15 bb, 2% pot) // a close spot: any top-2 action is "good"
grade   = good        if evLoss ≤ max(0.15 bb, 2% pot) or (close and chosen in top 2)
          smallMiss   if evLoss ≤ 10% pot
          leak        otherwise
quality = clamp(1 − evLoss / (0.25 × potBefore), 0, 1)
decision score (0–100) = 100 × weighted mean(quality), weight = log2(1 + potBefore/BB)
```

**Luck.** "All-in adjusted" chips: luck = actual net − Σ(equity × pot) at every all-in point. The review and the venue result show it next to chips, for example "Chips +420 (luck −60)".

**Limit, stated honestly.** EV depends on the hero continuation policy, so grades are relative to a strong reference player, not perfect play. The close-spot rule and the size of the tolerances keep this from punishing reasonable choices. Heavy tests check stability: the same spot graded with two seeds must give the same grade at least 95% of the time.

---

## 2. Theme packs

### 2.1 Format

A theme pack is a folder `<id>.allintheme/` containing `theme.json`, its assets, and `LICENSE.txt`.

```json
{
  "schemaVersion": 1,
  "id": "hearthwood",
  "name": "Hearthwood",
  "version": "1.0.0",
  "author": "All-In",
  "license": "CC0-1.0",
  "extends": null,
  "palette": { "ink": "#2A1E14", "parchment": "#F3E6C8", "gold": "#D9A441", "rune": "#7FE3FF",
               "suitRed": "#B3261E", "suitBlack": "#1B1B1B", "suitBlue": "#1F5FBF", "suitGreen": "#1E7A3C" },
  "slots": {
    "card.face":          { "procedural": "card.hearthwood", "params": { "frame": "gilded" } },
    "card.back":          { "procedural": "back.runeknot",  "params": { "hue": 0.08 } },
    "table.felt":         { "procedural": "felt.cloth",     "params": { "color": "#1F4D3A" } },
    "table.rail":         { "procedural": "rail.oak" },
    "table.runes":        { "procedural": "runes.ring",     "params": { "glyphs": "elder", "pulse": 0.6 } },
    "chip.1":             { "procedural": "coin.copper" },
    "chip.100":           { "procedural": "gem.ruby" },
    "avatar.grumli":      { "file": "avatars/grumli.png" },
    "sound.card.deal":    { "files": ["sfx/deal1.caf", "sfx/deal2.caf"] },
    "sound.chip.stack":   { "procedural": "sfx.clink",      "params": { "count": 3 } },
    "venue.tavern.map":   { "procedural": "venue.silhouette", "params": { "icon": "tavern" } }
  }
}
```

### 2.2 Slot catalog

`AssetSlot` is a Swift enum. It is the single source of truth for which slots exist.

| Group | Slots |
|---|---|
| Cards | `card.face` (template), `card.face.<rank><suit>` (optional full override), `card.court.<J/Q/K><suit>` (optional art), `card.back`, `card.back.<rewardID>` |
| Table | `table.felt`, `table.rail`, `table.runes`, `table.light`, `table.dealerButton`, `table.shoe` |
| Chips | `chip.<denomination>` for 1, 5, 25, 100, 500, 1k, 5k, 25k (copper, silver, gold coins; ruby, sapphire, emerald, diamond, dragonstone gems) |
| Characters | `avatar.<characterID>` (portrait with `idle/think/happy/tilt` states), `character.<id>.full` (boss art) |
| Venues | `venue.<id>.map`, `venue.<id>.banner`, `venue.<id>.background`, `venue.<id>.stamp` |
| Audio | `sound.<event>` (deal, flip, chip.bet, chip.stack, pot.sweep, win, allin, timer, ui.tap, ui.success, ui.fail, stamp), `music.<venueID>` |
| UI | `ui.button.frame` (9-slice), `ui.panel.parchment`, `font.display`, `font.body` |
| Effects | `fx.coinBurst`, `fx.magicSparks`, `fx.embers`, `fx.confetti` (particle parameters) |

### 2.3 How slots resolve

`ThemeResolver.resolve(_ slot: AssetSlot) -> AssetSource` returns `.file(URL)`, `.procedural(ProceduralID, Params)` or `.files([URL])`.

Lookup order: user-selected pack → the packs it `extends` → built-in `hearthwood` → `CodeDrawn.default(slot)`. The last step is a Swift switch that covers every slot, so **a missing asset can never crash or blank the screen.** Characters and venues refer to art by `artKey`, so an illustrated pack swaps art without any code changes.

### 2.4 Validation

`allin-tool theme validate <path>` also runs inside `ThemeKitTests` for every pack in `Themes/`. It checks:

- the schema version, that every slot id is known, and that `extends` resolves;
- that every file exists, has the right format (PNG or HEIC for images; CAF or M4A for audio), and has the right size and aspect ratio for its slot: card 5:7 at ≥ 500×700 px; avatar square at ≥ 512 px with alpha; SFX ≤ 3 s; music loops ≤ 3 MB;
- palette contrast: each suit color against the card face must be ≥ 4.5:1, and the four-color deck must keep the suits distinguishable;
- that a `license` field and `LICENSE.txt` are present;
- that the total pack size is ≤ 150 MB.

Shipped packs live in the bundle. Importing a user pack (to Application Support, through the sandboxed file importer) is post-v1.

### 2.5 Code-drawn default art (v1)

- **Cards:** Core Graphics vector art. Large corner indices, standard pips, and court cards drawn as a crest (crown, helm or circlet glyph plus the letter) inside a gilded frame. The back is a procedural rune-knot pattern. Each card is rendered once per scale into a texture atlas.
- **Table:** an oval carved-oak rail (procedural wood grain shader), cloth-noise felt, and an inner ring of runes that glow through an `SKShader` with a time uniform and a pulse on street changes. Warm candle vignette.
- **Chips:** coins with embossed rims and gem cut facets. Stacks are built from denominations.
- **Avatars:** heraldic medallions with each character's sigil (axe, leaf, gear, staff), a color ring and mood animations. Bosses use a large sigil silhouette until illustrated art arrives.
- **Sound:** SFX synthesized with AVAudioEngine (filtered noise for card flicks, FM bell partials for coin clinks). Optional CC0 samples can be added later (see the open questions). No music in v1.

---

## 3. Rendering, animation and feel

### 3.1 What uses SpriteKit and what uses SwiftUI

| Surface | Technology | Why |
|---|---|---|
| Poker table (play, lessons, review replay, boss, arena, tournament) | **SpriteKit** `TableScene` inside `SpriteView`, with SwiftUI overlays for panels and the action bar | many moving nodes, particles, shaders, timed actions, stable 120 fps |
| Main menu drifting cards and coins | SpriteKit `MenuBackgroundScene` | particles and parallax |
| Career map | SwiftUI `Canvas` for the path, `KeyframeAnimator` for the walking token, a small SpriteKit overlay for confetti and coins | mostly static art with one choreographed sequence |
| Menus, panels, lessons, Gym, stats, settings | SwiftUI | layout, text, accessibility |
| Explainers and sandbox bars | SwiftUI `Canvas` + `TimelineView` + springs | data-driven and parameter-bound |
| Glows on buttons and venues | SwiftUI `.layerEffect` with Metal `ShaderLibrary` | cheap and local |
| Charts (review EV bars, decision score over time) | Swift Charts | built in |

There is one `TableScene` with modes `.live`, `.spot` (lesson puzzle, fixed state), `.replay(log)` and `.miniature`. It is the same code everywhere, so the table looks identical in lessons and in play.

### 3.2 Key animations

All durations scale with the game speed setting.

| Moment | Animation |
|---|---|
| Deal | cards flick from a carved dragon-head shoe in an arc with a spin, 90 ms apart, with a "deal" sound |
| Bet | coins slide from the seat to the bet line and settle into a stack with a clink |
| Street change | bets sweep into the pot; the rune ring pulses; flop cards slide out face down then flip (x-scale flip with a slight lift) |
| Bot thinking | the medallion breathes; small personality idles (Zib fidgets, Vexa stays still, Grumli drums his fingers); a candle timer burns when the timer is on |
| All-in | the camera eases in, the runes flare, the runout slows, and optional equity bars float over the seats |
| Showdown | the winning best five lift and glow gold, the others dim, and a ribbon shows the hand name; the pot bursts as coins toward the winner |
| Career | the lantern token walks the path; the next venue lights up; coins and confetti fall |
| Venue result | coin rain; a wax-seal passport stamp slams down with a small screen shake |
| Lessons | pot slices, outs lighting up in a fanned deck, best-five highlight, "who calls me" range split; sandbox bars spring toward converging values |
| Gym | range grid cells pulse green or red; the combo counter ticks up |

### 3.3 Performance targets

- 120 fps on ProMotion displays and 60 fps elsewhere, with table frame time ≤ 8 ms on M1.
- Table under 300 nodes and under 40 draw calls (atlases for cards, coins and glyphs).
- Launch to main menu < 1.5 s. No compute on the main actor (enforced by review, and checked with Instruments in M7.8).

### 3.4 Reduce motion

On when either the system `accessibilityReduceMotion` or the in-app setting is on.
- Movement becomes short crossfades.
- No particles, parallax, camera moves or screen shake.
- Card flips become instant reveals.
- Glow stays, but static.
- The sound still plays.

### 3.5 Keyboard shortcuts

Also listed in the menu bar through `Commands`.

| Key | Action |
|---|---|
| F | Fold |
| C | Check/Call |
| R | Raise (focuses the size field) |
| ↑ / ↓ | Change size by one step |
| 1–5 | Size presets (⅓, ½, ⅔, Pot, All-in) |
| Return | Confirm |
| H | Hint |
| A | Advisor orb (Arena) |
| Space | Next hand / continue |
| ← / → | Step through a review |
| ⌘L | Last hand review |
| Esc | Table menu |

### 3.6 Window

Base layout is 1120×700 pt, matching the wireframe frame, which is also the minimum window size. The window is resizable and supports full screen. The table scales with `aspectFit`. Panels reflow.

---

## 4. Fantasy reskin of the approved screens

The layout, flow and controls of every screen stay exactly as in the wireframe. Only names, art and voice change.

**Name mapping:**

| Wireframe | Fantasy |
|---|---|
| Kitchen Table | Village Tavern ("The Gilded Tankard") |
| The Club | Guild Hall |
| The Casino | Royal Keep |
| High Roller | Dragon's Hoard |
| Carl (station) | Grumli Stonefist, Dwarf |
| Mia (maniac) | Zib, Goblin |
| Rita (rock) | Vexa Moonwhisper, Elf |
| Ben (nit) | Brother Mott, Gnome Monk |
| "The Prof" (balanced) | Archmage Oryn |
| ??? (locked) | Ysolde, the Elder Dragon |
| Coach | Hoot, the Owl Familiar (asks questions) |
| Chips / bankroll | gold (coins and gems); poker terms unchanged |
| Ranks | Tavern Regular → Guild Journeyman → Keep Knight → Dragon-Slayer |
| Passport | Adventurer's Journal with wax-seal stamps |

| # | Screen | Fantasy version (same layout as the wireframe) |
|---|---|---|
| 1 | Main menu | Title "ALL-IN" in gilded display type over a candle-lit tavern table with drifting cards and coins. Buttons: **Continue Career** (tag "Village Tavern · 3/10"), Quick Play, **The Arena** (new, see §5), Training Gym, Rivals, My Game, Settings. "Today" card is a parchment note: 5-minute warm-up, next lesson, streak shown as a lantern flame. Top right: medallion, name, rank, gold. |
| 2 | Career map | Illustrated realm map (code-drawn silhouettes in v1). Dashed road from the Tavern (village) to the Guild Hall (stone town hall) to the Royal Keep (castle) to the Dragon's Hoard (mountain cave). Locked venues are fogged. Bottom panel "What each venue teaches" keeps the wireframe text with the new names. |
| 3 | Venue chapter | Banner with the venue host waving (Tavern: "Marta the Innkeeper: *Pull up a stool, traveler.*"). Node list with icons: 📘 Lesson becomes a scroll, 🎯 Drill a target dummy, 🃏 Table session a tankard, 👊 Boss a crossed-swords crest. Right panel: chapter skill meters as filling rune bars. |
| 4 | Lesson puzzle | Same carved table, opponent at the top (for example "Vexa · bets 50"), board, pot tag, hero cards. Coach panel shows Hoot on a perch. Action bar: Fold / Call / Raise, plus "💡 Hint (−1★)". Step progress "Step 2/5". |
| 5 | Lesson explanation + sandbox | Left: verdict ribbon ("✓ Good call, +1.8 bb on average") and the animated explainers. Right: "🧪 Alchemist's Bench: break it yourself" with draggable cards, a bet slider and the "Price you need" and "Your chance" bars. Footer: "Next: try 3 spots on your own →". |
| 6 | Play table (6-max) | Oak table with runes. Top-left tags "Cash 6-max · 1/2", "Hand #23". Top-right "🦉 Coach: ON", "HUD: basic", "Last hand ↺". Seats are medallions with name, stack and a style hint ("calls a lot"). Coach box "Think first" with the 3 questions and "Show her range" / "I'm fine". Action bar exactly as the wireframe: Fold, Call, Raise to, ⅓ ½ ⅔ Pot All-in, slider, "⏱ no timer". |
| 7 | Hand review | Header "Hand #22 review · You won 140 · decisions: 3 good, 1 leak". Street timeline as wax-sealed tags (green "✓", red "✗ −3.1 bb"), with replay controls. Left: miniature table replay with villain cards revealed. Right: explanation using the villain's style, EV bar chart per action, buttons "Replay this spot", "Add to my Gym", "Notes on Grumli". |
| 8 | Boss intro | Lights dim; a spotlight shader on the boss. Full-body slot (sigil silhouette in v1, idle animation). "VILLAGE TAVERN · BOSS", name, quote, "To clear the Tavern" requirements, "Take the seat" / "Not yet". |
| 9 | Venue result | "Tavern cleared!", the boss's reaction line, ★★☆. Two panels: boss session (decision score, chips with luck, key misses) and exam spots with skill bars. Celebration of coin rain, journal stamp and a reward (card back or felt). "Review boss hands" / "To the Guild Hall →". |
| 10 | Quick Play lobby | Five format cards: Cash 6-max, Full Ring, Heads-Up, Sit & Go, Tournament. In v1, Full Ring, SNG and Tournament show "Opens with the Guild Hall/Royal Keep update" and are disabled. Opponents row of medallions with style tags, plus "random mix". Table strength slider. Options: stakes, coach, HUD, speed. "Sit down". |
| 11 | Tournament table (M9) | Top bar on a banner with blinds and level timer (a sand hourglass pulses near level end), players left and paid, stack in BB, "Standings". Coach panel "Bubble pressure" with "Show the ICM picture". Action bar with "All-in 17 BB". A "Bubble" banner unfurls at the money bubble. |
| 12 | Training Gym | "The Training Yard". Drill list (Smart mix first, then drills; locked ones show the venue that unlocks them). Right: active drill (for example the range painter grid, or Tavern drills), with combo flame and Check / Explain. |
| 13 | Rivals | Roster of six medallion cards. Detail: stat bars hidden as "???" until discovered by playing; "Your notes" plus auto-notes; "How to beat this style" asked as a question; "Heads-up vs Grumli". |
| 14 | My Game | Skill radar with eight axes (Rules, Position, Math, Ranges, Bet sizing, Reading players, Tournaments, Mental game). Top leaks with "Fix in Gym". Decision score over time against chips won. Adventurer's Journal with venue stamps, hands played, sessions, hand history. |
| 15 | Settings | Sections: Gameplay, Coach, Display & animation, Sound, Data & backup. Rows exactly as the wireframe: speed, action timer, bet-size buttons (editable), four-color deck, reduce motion, keyboard shortcuts, export/import. Note "Fully offline: no accounts and no network." Also a Theme picker under Display. |

---

## 5. New Play section: "The Arena"

The Arena reaches the main menu in M7. Quick Play is casual play against the personality bots. The Arena is play against machine intelligence. All of it runs offline.

| Opponent | Arrives | Machine intelligence |
|---|---|---|
| **Morwen, the Mirror Witch** | v1 (M7) | adaptive AI that learns your tendencies and exploits them |
| **Ysolde, the Elder Dragon** | M10 | near-GTO heads-up blueprint |
| **The Seeing Stone** (advisor orb) | M11 | sparring advisor available at any Arena table |

### Screens (wireframe level, in the approved style)

**A1. Arena hub**
- *Left:* three large character cards (Morwen, Ysolde, Seeing Stone sparring). Each has a format picker (Heads-Up or 6-max for Morwen; Heads-Up for Ysolde) and a "Duel" button. Cards not yet available are hidden by a feature flag, not shown greyed out.
- *Right:* panel "Your duel record": per opponent, hands played, decision score, bb/100 with a confidence band, and luck.
- *Bottom:* toggle "Seeing Stone: Off / On request" and "Reveal her reads: After hand / End of session / Never".
- *Note:* the primary button always points at the next thing to do (wireframe rule).

**A2. "What Morwen has learned about you"**
- A grid of tendency cards, for example "You fold to flop c-bets 68% (n = 41)" with a confidence ring.
- Each card says how she uses it ("She c-bets more often against you") and offers "Fix in Gym".
- A trend line per tendency shows whether you are getting better.
- Reachable from the hub and from the duel summary.

**A3. Arena table**
- The standard table screen (screen 6) plus:
  - a small mirror charm on Morwen's medallion that glints when she makes an exploit decision (the reason is revealed according to the setting);
  - an orb button at top right (key A, M11).
- No coach questions by default. The coach can be turned on from the lobby options.

**A4. Seeing Stone overlay (M11)**
- A side panel slides over the coach position. It shows:
  - action frequencies from the strong reference strategy (for example "Fold 10% · Call 55% · Raise ⅔ 35%");
  - EV per action against Morwen's current read of your range and of her own, as a bar chart;
  - three "why" lines built from templates (range advantage, equity versus price, blockers, SPR, MDF);
  - a mini range-versus-range grid on request.
- Footnote: "Hands where you ask the Stone are marked *assisted* and don't count toward your duel record."

**A5. Duel summary**
- Decision score, bb/100, luck.
- "Her exploits this session": a list with the cost to you in bb, for example "Bluffed you off the turn 4×: −6.2 bb".
- The top 3 leaks with "Fix in Gym".
- Buttons: "Review hands", "Rematch".

---

## 6. Curriculum as data

### 6.1 Content layout

```
Content/
  skills.json                    micro-skills → radar axes, base difficulty
  characters/<id>.json           personality params, artKey, barks, bio, "how to beat" question
  venues/tavern/venue.json       nodes (order, type, unlock rules), host, meters shown, boss and exam ref
  venues/tavern/lessons/<id>.json
  venues/tavern/spots/<id>.json  spot templates (generators)
  venues/tavern/drills/<id>.json
  venues/tavern/boss.json, exam.json
```

The Xcode project copies `Content/` into the bundle as a folder. It is loaded with `Codable`. Every file has `"schemaVersion"`. IDs are dotted strings and never change once released (progress is keyed by them).

### 6.2 Spot templates (the anti-memorization core)

A spot template is a **generator**: constraints plus an evaluation method. It never stores an answer.

```json
{
  "schemaVersion": 1,
  "id": "tavern.value.river-bet-or-check",
  "skill": "value.bet-or-check",
  "difficulty": 0.35,
  "table": { "players": 2, "stacksBB": [40, 150], "blinds": "1/2" },
  "hero": { "position": "BTN",
            "hand": { "madeHand": ["topPair", "overpair", "twoPair", "middlePair", "noPair"] } },
  "villain": { "character": "bram", "line": "checkThrough" },
  "board": { "street": "river", "exclude": ["monotone"] },
  "potBB": [6, 24],
  "question": { "type": "action", "options": ["check", "bet:0.5", "bet:1.0"] },
  "evaluation": { "method": "policyEV" },
  "quality": { "minGapBB": 0.3, "answerBalance": { "check": [0.3, 0.7] } },
  "prompt": "{villain} checked to you on every street. You have {heroHandName}. Bet or check?",
  "explain": [{ "explainer": "whoCallsMe", "bind": { "range": "villainRange", "hand": "hero" } }],
  "variation": ["suits", "seats", "stacks", "villainName"]
}
```

**How generation works:**
1. **Predicates.** `HandPredicate` covers made-hand class, draws, pairs and suitedness. `BoardPredicate` covers texture, street, high card and "flush possible". `SituationPredicate` covers position, line, pot and SPR.
2. **Sampling.** The generator rejection-samples cards that satisfy all predicates, up to 2,000 tries. A template that fails validation is rejected (see §6.5).
3. **Legal by construction.** The generator builds the action prefix (for example check-check-check), and the instance is produced by replaying `HandReducer`.
4. **The answer is computed.** `SpotEvaluator` computes it with one of: `showdownWinner`, `bestFive`, `nuts`, `beatsMeCount`, `potCount`, `legalSizes`, `nextToAct`, `closedFormEV`, `policyEV`, `rangeMatch`, `pushFold`.
5. **Variation.** Suits are permuted, seats rotated, stacks sampled and opponent names rotated, all within the template's constraints.

**Question types:** `action` (with sizes), `pickWinner` (including "split"), `pickCards` (select the nuts or outs on a fanned deck), `pickHandClass`, `number` (estimate, with a tolerance band), `rangePaint`, `sizeChoice`. Multiple-choice text questions exist but are reserved for occasional rule checks.

**Fingerprints and spaced repetition.**
- Each instance has an `instanceHash` (exact cards, stacks and line). An instance never repeats within 60 days.
- Each instance also has a `DecisionTypeKey` = `templateID#answerClass` (for example `tavern.value.river-bet-or-check#check`).
- Spaced repetition schedules **decision types, not instances**, so a missed spot returns as a new instance of the same type.

### 6.3 Lessons

```json
{
  "id": "tavern.l7.bet-when-worse-calls",
  "title": "Bet when worse hands call",
  "skills": ["value.bet-or-check"],
  "steps": [
    { "kind": "hook",    "spot": "tavern.value.river-obvious" },
    { "kind": "puzzle",  "spot": "tavern.value.river-bet-or-check", "coach": "Who would call you here?" },
    { "kind": "explain", "explainers": ["whoCallsMe"], "thinking": "Before betting, split their hands into better and worse. Bet if enough worse hands call." },
    { "kind": "sandbox", "controls": ["heroCards", "board"], "meters": ["worseThatCall", "betterThatCall"],
      "challenge": "Find a hand where betting stops being worth it." },
    { "kind": "apply",   "spot": "tavern.value.river-bet-or-check", "count": 3, "freshSeeds": true }
  ],
  "stars": { "hintCost": 1, "threeStars": "puzzle good and apply ≥ 3/3 good" }
}
```

Five steps match the wireframe's "Step n/5": hook, puzzle, explain, sandbox, apply.

The explainers are a fixed Swift library (`AllInUI/Explainers/`). Content picks one and binds its parameters. Text placeholders (`{villain}`, `{heroHandName}`, `{priceNeeded}`) resolve against the computed instance. A placeholder that does not resolve fails validation.

### 6.4 Skill model, meters and spaced repetition

**Micro-skills** (in `skills.json`) roll up to the eight radar axes with weights.

**Ratings (Elo-style):**
- each skill has a rating θ, and each spot has a difficulty d (template base plus instance features, for example a smaller EV gap is harder);
- expected = σ(θ − d); outcome = decision quality in [0, 1];
- θ += K·(outcome − expected), with K = 0.4 that decays to 0.1 as evidence grows;
- displayed meter = σ(θ − d_ref) as 0–100%;
- **mastered** = meter ≥ 80% with ≥ 15 pieces of evidence.

Lesson completion alone never moves a meter (wireframe rule).

**Spaced repetition:**
- FSRS-5, ported from Kata, with decision types as the cards.
- Grade mapping: leak → Again; small miss → Hard; good → Good; good, fast and no hint → Easy.
- Missed decisions from play and review ("Add to my Gym") also enter the deck as their `DecisionTypeKey`.

**Gym Smart mix and Today warm-up (`DrillScheduler`):** due decision types first, then the weakest unmastered skills in unlocked venues, then new material. The warm-up is 10 spots, about 5 minutes.

**Coach hint fading (`CoachEngine`):**

| Meter | Coach behavior |
|---|---|
| below 40% | full three questions plus "Show her range" |
| 40–75% | questions only |
| above 75% | hidden unless asked |

At the table the three "think first" questions map to the skills *ranges*, *equity* and *action purpose*. In the Tavern they are worded in beginner terms.

### 6.5 Authoring workflow (no code needed)

1. Write or modify JSON in `Content/`, following `docs/CONTENT_GUIDE.md`.
2. Run `swift run --package-path Packages/AllInKit allin-tool content validate`. It checks:
   - schema and references;
   - unlock graph reachability;
   - placeholders resolve;
   - for each template, 500 generated instances where every one succeeds, `answerBalance` holds, `minGapBB` holds for at least 90% of them (so spots are not ambiguous), and evaluation is fast enough (p95 < 50 ms).
3. Preview with `allin-tool content preview tavern.value.river-bet-or-check --n 8 --seed 1`, which prints ASCII spots with computed answers and EVs.
4. Coverage with `allin-tool content stats` (spots per skill, difficulty histogram).
5. In the app (DEBUG): launch with `-AllInContentPath <repo>/Content` to hot-load content, and use the hidden **Content Lab** screen to play any node, template or seed.
6. `ContentTests` runs the same validator, so `Tools/test.sh content` is the gate.

### 6.6 v1 curriculum: Village Tavern (10 nodes)

**Tavern skill meters:** Rules & flow, Hand ranks, Board reading, Betting for value.

| # | Node | Type | Thinking skill built | Micro-skills | How it's tested |
|---|---|---|---|---|---|
| 1 | A hand in four rounds | Lesson | "Where are we and who acts?" Blinds, preflop/flop/turn/river, action order, check vs call | `rules.flow`, `rules.actions` | spots from random legal states: "who acts next / which actions are allowed / what does calling cost" (`nextToAct`, `legalSizes`) |
| 2 | Five cards make a hand | Lesson | Build the best five of seven; the ladder of hand ranks; kickers; when the board plays (split) | `ranks.best5`, `ranks.kicker-split` | `pickWinner` (incl. split), `pickCards` for the best five; sandbox swaps cards and highlights the best five live |
| 3 | Which hand wins? | Drill | Fast, confident comparison with tricky kickers, counterfeits and board-plays | `ranks.compare`, `ranks.kicker-split` | timed reps, combo counter; spaced repetition per answer class (e.g. `#split`, `#kicker`) |
| 4 | Check, bet, call, raise | Lesson | Money flow: what's in the pot, what an action costs, min-raise and all-in rules | `money.pot-count`, `money.legal-sizes` | `number` (pot after the line), `sizeChoice` (legal min-raise); sandbox: change bets and watch the pot and legal range update |
| 5 | Read the board | Lesson | "What's the best possible hand here?" Flush, straight and full house possible | `board.nuts`, `board.texture` | `pickCards` for the nuts, `pickHandClass`; sandbox: change the board and watch "possible hands" runes light up |
| 6 | What beats me? | Drill | Relative strength: same hand, different boards | `board.what-beats-me` | `beatsMeCount` buckets (none / a few / many), `pickHandClass` |
| 7 | Bet when worse hands call | Lesson | "Who calls me?" Split the opponent's hands into better and worse (first contact with ranges) | `value.bet-or-check` | `policyEV` vs Bram's known policy; explainer `whoCallsMe`; apply 3 fresh |
| 8 | When the quiet one bets | Lesson | "What does a bet mean from *this* player?" Bram only bets strong, so count how many of his betting hands you beat | `reading.bet-means-strength` | `policyEV` fold/call vs Bram's betting range; explainer `whoCallsMe` reversed ("hands he bets that you beat") |
| 9 | Tavern night | Table session | Use everything at a live 6-max table with Hoot asking the three questions | all Tavern skills | 40 hands vs Bram plus 4 tavern patrons (loose beginners); graded; meters update; completing it unlocks the boss |
| 10 | Boss: Bram Ironmug, Tavern Champion | Boss + exam | Bram plays many hands, calls with any pair, **bets only when strong, never bluffs.** To beat him: value-bet your made hands, fold when he wakes up | all | heads-up, 30 hands, no coach, at least 15 graded decisions, decision score ≥ 65; then **exam:** 12 fresh spots across all Tavern micro-skills, pass ≥ 10/12. Stars: ★ pass, ★★ score ≥ 75 and exam ≥ 11, ★★★ score ≥ 85 and 12/12 |

**Tavern Gym drills:** Which hand wins?, Count the pot, Find the nuts, What beats me?, Bet or check? (river). Later drills from the wireframe list appear locked with "Unlocks in Guild Hall" or "Unlocks in Royal Keep".

**Characters used:** Marta (host, no seat), Bram (boss), and four patrons that are presets of the loose-beginner style with different names and art keys. Rivals (Grumli, Zib, Vexa, Mott, Oryn) are available in Quick Play from day one.

### 6.7 Later venues (content milestones)

| Venue | Topics (boss) |
|---|---|
| Guild Hall | position, starting hands, pot odds, outs, c-bets (boss: Grumli, station; lesson: stop bluffing, value-bet thinner) |
| Royal Keep | ranges, equity, bet sizing, multi-street plans, player types, tournaments and ICM (boss: Sir Cedric, the Knight-Captain, a solid tournament player) |
| Dragon's Hoard | balance vs exploit, bluff ratios, deep stacks, final tables, mental game (boss: Ysolde, near-GTO) |

---

## 7. Bots and machine intelligence

All of them implement:

```swift
public protocol StrategyProvider: Sendable {
  func distribution(for ctx: DecisionContext, hand: HoleCards) -> ActionDistribution  // pure
}
```

Sampling is separate (`BotSeat` + `SeededRNG`). Range inference, grading and the advisor can therefore read the full strategy.

### 7.1 Personality bots (v1, M2)

`PersonalityParams` is Codable and lives in `Content/characters/*.json`. Its fields:

- *Preflop:* `vpip`, `pfrRatio`, `threeBet`, `foldTo3Bet`, `positionAwareness`. Opening ranges are the top x% of a fixed preflop ordering, x set by position and looseness, with a small amount of shape noise.
- *Postflop:* `cbet`, `barrel`, `bluffFreq`, `valueThreshold`, `continueThreshold` (equity against the perceived range relative to price), `stickiness` (station factor: ignores the price), `slowplay`, `sizing` profile (per hand-strength bucket, for example a maniac overbets), `readSkill` (how well the bot narrows the hero's range), `randomness`.

**How a postflop decision is made:**
1. `HandFeatures` classifies the bot's hand: made class, draw outs and the board texture.
2. The bot estimates its equity against the hero's perceived range (`RangeTracker` with `readSkill` blur).
3. Thresholds mixed into probabilities give the `ActionDistribution`.

| Character | Style | Key params |
|---|---|---|
| Grumli | calling station | vpip .55, stickiness .9, bluff .03 |
| Zib | maniac | vpip .6, pfrRatio .8, bluff .45, overbets |
| Vexa | rock | vpip .14, bluff .05, continue high |
| Mott | nit | vpip .10, foldTo3Bet .8, cbet only strong |
| Oryn | balanced | uses `BaselineStrategy` |
| Bram (Tavern boss) | loose-passive, never bluffs | vpip .45, bluff 0, valueThreshold high |
| Patrons | loose beginners | random draws around vpip .5, low readSkill |

**Table strength slider:** blends the params toward Oryn (stronger) or toward random noise (weaker). "Matches your level" picks the blend from the user's average meter.

### 7.2 BaselineStrategy (Oryn, and the reference continuation policy)

A strong heuristic strategy, not GTO:
- *Preflop:* position-based open, 3-bet and defend ranges. These are generated by `allin-tool gen-preflop-ranges` from an equity-realization model (equity × position realization factor against the expected calling range), not hand-typed charts.
- *Postflop:*
  - value-bet when equity against the calling range exceeds a threshold;
  - bluff with a value:bluff ratio matched to the bet size (pot/(pot + 2·bet) for a river bluff), choosing blockers and draws first;
  - defend at roughly MDF against a balanced opponent, adjusted for range advantage from `BoardAnalyzer`;
  - sizes chosen by texture (small on dry boards where the bettor has range advantage, large on wet and polarized boards).

It is the hero continuation policy for EV grading, the baseline for the adaptive AI, and the advisor's fallback before blueprints exist.

### 7.3 Adaptive exploitative AI: Morwen (v1, M7)

**1. Player model (`PlayerModel`, persisted for the user).**
- Counters per `SituationKey` = street × position (IP/OOP) × preflop role (aggressor/caller) × facing (none/bet/raise) × size bucket × SPR bucket. Each key holds Beta/Dirichlet action counts (fold/call/raise, check/bet with size).
- Shrinkage toward a population prior of "typical learner" (prior weight 20 hands). Back-off from fine keys to coarse keys when data is thin.
- Exponential decay of 0.997 per hand, so the model notices when the user fixes a leak. That matters because this is a learning app.
- Showdown evidence: hands revealed at showdown update `P(strengthBucket | line)` tables.

**2. Range inference.**
- Preflop: the user's range comes from VPIP and PFR per position, shaped by showdown evidence.
- Postflop: `RangeTracker` uses the *modeled* user policy (strength bucket × line → action probabilities) as the likelihood.

**3. Best response.**
For each candidate action, EV is computed against the inferred range, using the modeled response frequencies (for example the user's fold-to-turn-bet rate in this key) and two-street rollouts with model-based policies.

**4. Safe blending.**
- Policy = (1 − λ)·Baseline + λ·BestResponse, with λ = confidence(n) × cap.
- confidence(n) = n / (n + 30). The cap is 0.8 on Hard, 0.5 on Normal and 0.3 on Easy.
- This keeps Morwen beatable and not wildly exploitable.

**5. Explanations.** Each exploit decision is tagged with an `ExploitReason` (for example `.overFoldsToTurnBet(freq: 0.71, n: 38)`). Tags power the mirror glint, screen A2 and the duel summary.

**Honest limits.** The model needs a few hundred hands before its reads become sharp. Exploits are as good as the model buckets. In 6-max, Morwen models only the user. The other seats are known personality bots, which she reads exactly from their params.

### 7.4 Near-GTO pipeline: Ysolde (M10, heads-up first)

**Tooling:** the `Solver` library plus the `allin-solve` CLI, built in release mode and run on the owner's Mac. Validation ladder:
1. Kuhn poker reaches game value −1/18.
2. Leduc hold'em exploitability goes below 0.01 chips per hand.
3. Then heads-up NLHE.

**Algorithm:** external-sampling MCCFR with Linear CFR weighting and regret-based pruning. Multithreaded with lock-free atomic regret updates. Regrets are `Int32`; the average strategy is `Float`.

**Abstraction:**

| Part | Choice |
|---|---|
| Stacks | 100 bb, plus 25 bb and 50 bb variants for tournaments/short stacks (later) |
| Preflop cards | lossless, 169 classes |
| Flop / turn cards | k-means (earth mover's distance on equity histograms) over isomorphic hands: 256 flop and 256 turn buckets. Bucket maps are indexed by a Waugh-style hand isomorphism indexer (1,286,792 canonical flop and 13,960,050 turn combos), shipped as `UInt8` maps of about 1.3 MB and about 14 MB |
| River cards | no bucket map shipped (123M combos). River uses the real-time resolver; the blueprint river fallback uses 8-cluster opponent-equity buckets computed on the fly |
| Actions, preflop | fold, call, 2.5×, 3.5× (3-bet 3×), all-in; at most 4 raises |
| Actions, postflop | check, bet 33% / 75% / 150%, all-in; raises 2.5× / all-in; at most 3 raises per street |
| Off-tree bet sizes | pseudo-harmonic action translation |

**Compute and storage estimates.** These must be validated in a sizing spike (M10.3) before committing:
- about 10–40M infoset-actions;
- training memory ≤ 1.5 GB;
- 1–3 days on an M-series Max;
- strategy quantized to 8 bits per action and LZFSE-compressed: about 20–60 MB, plus about 15 MB of bucket maps;
- **ship budget ≤ 500 MB** (owner decision, 2026-11-04). Spend the extra room on finer buckets and more bet sizes, not on padding; the M10.3 sizing spike picks the abstraction that fits.

**File format (`.allinbp`).** Header (magic, version, game config, abstraction ids and hashes, bucket counts), an infoset index (minimal perfect hash of the action sequence → offset), and quantized strategy rows. It is memory-mapped at runtime (`Data(contentsOf:options: .alwaysMapped)`), so lookup is O(1) and needs no load time.

**River resolver (`RiverResolver`).**
- Beliefs at the start of the river come from Bayesian updates through the blueprint policy.
- It solves the river subgame with vectorized CFR+ over all 1326 hands (Accelerate/SIMD), card-removal aware, with sizes 33/75/125%/all-in and at most 2 raises.
- 400 iterations, target < 1.5 s on M1, run inside the bot's think time.

**Quality gates:**
- beats every personality bot and `BaselineStrategy` by a significant margin over 200k simulated hands (95% CI above 0);
- Local Best Response (LBR) exploitability measured and reported in `docs/AI_REPORT.md`;
- no claim of "GTO" in the UI. The copy says "plays a near-equilibrium strategy".

**6-max and full ring (M13), honestly not GTO.** No equilibrium is meaningful or computable here.
- Preflop: an MCCFR solve of the 6-max and 9-max *preflop* game, with postflop values approximated by equity × position realization. This yields per-node 169-hand frequencies of a few MB.
- Heads-up pots postflop: mapped onto the HU blueprint with state translation (approximate when stack or position differ), and the river resolver.
- Multiway pots: `BaselineStrategy`.
- The marketing copy says "strong", never "unbeatable" or "GTO".

### 7.5 The Seeing Stone advisor (M11)

- **Input:** the current state, the hero's hand, and the opponents' tracked ranges.
- **Reference strategy:** the blueprint frequencies if available (HU), otherwise `BaselineStrategy` frequencies.
- **EV against current reads:** `ActionEVEstimator` against the modeled opponent. When the reference and the exploit disagree, the advisor shows both: "Balanced: call. Against Morwen's read: raise, because she over-folds."
- **Why lines:** `ReasonBuilder` turns computed features into text from templates in `Content/reasons.json`. Features: equity vs range against the price; range and nut advantage; MDF; blockers (combos removed); SPR and commitment; position; the opponent's tendency. It picks the top 3 by contribution to the EV gap. No LLM.
- **Budget:** < 400 ms using cached rollouts, with a progressive display.
- Use is logged; the hand is marked assisted.

---

## 8. Persistence (AllInStore)

SwiftData uses `VersionedSchema` and a `MigrationPlan` from V1. The store follows Kata's `ProgressStore` pattern (explicit saves, no relationship graphs).

| Model | Contents |
|---|---|
| `Profile` | name, gold, rank, streak, created date, selected theme |
| `SkillState` | skillID, θ, evidence count, last updated |
| `DecisionCard` | DecisionTypeKey, FSRS state, last instanceHash list |
| `NodeProgress` | nodeID, status, stars, best score |
| `SessionRecord` | kind (career/quick/arena/boss/exam), format, start/end, decision score, net, luck, assisted flag |
| `HandRecord` | handID, session id, summary fields (net, pot, grades), `log: Data` (event log JSON compressed with LZFSE), seed |
| `RivalKnowledge` | characterID, hands vs, discovered stat estimates, notes, auto-notes |
| `PlayerModelSnapshot` | Codable blob of Morwen's model of the user, versioned |
| `Unlock` | rewardID (card back, felt), date |

Settings use `@AppStorage`/UserDefaults. **Export/import** writes a single `.allinsave` JSON (all models plus a schema version) through `fileExporter`/`fileImporter`. The sandbox entitlement `user-selected.read-write` covers this.

**App Store setup:**
- entitlements are `app-sandbox` and `files.user-selected.read-write` only; no network client;
- hardened runtime;
- `PrivacyInfo.xcprivacy` with no tracking, no collected data, UserDefaults reason CA92.1, file timestamp reason C617.1;
- category `public.app-category.card-games`, secondary education.

---

## 9. Testing strategy

| Layer | Tests (Swift Testing) | Run with |
|---|---|---|
| Cards/RNG | parsing round-trip, deck uniqueness, shuffle determinism per seed, χ² uniformity on 1M shuffles (heavy) | `unit`, `heavy` |
| Evaluator | golden hands per category; tie and kicker cases; agrees with `NaiveEvaluator` on 1M random 7-card hands; **full enumeration of all 133,784,560 7-card hands** gives exact category counts (SF 41,584 · Quads 224,848 · FH 3,473,184 · Flush 4,047,644 · Straight 6,180,020 · Trips 6,461,620 · Two pair 31,433,400 · Pair 58,627,800 · High 23,294,460); 7,462 distinct 5-card classes; speed ≥ 10M/s | `unit`, `heavy` |
| Rules/reducer | unit cases: HU blind order, min-raise, incomplete all-in doesn't reopen, uncalled bet return, BB ante; **property tests over 100k random hands** (2/6/9 seats, random stacks, random legal actions): chip conservation, no negative stacks, pot = Σ contributions, `legalActions` non-empty when someone must act, the hand always terminates, replay(events) == final state, a seat-filtered log never contains another seat's hole cards before showdown | `unit` (10k), `heavy` (100k) |
| Pots | side pots vs a brute-force reference on random contribution vectors; split pots and odd chip | `unit` |
| Equity | AA vs KK ≈ 82% (±0.3); exact vs Monte Carlo within 3σ; range vs range symmetry (A vs B + B vs A = 1 − ties); card removal | `unit`, `heavy` |
| Host | scripted seats reproduce logged hands; timeout → check/fold; illegal action handled; visibility per seat | `unit` |
| Bots | each personality vs `RandomSeat` > 0 bb/100 over 20k hands; Oryn beats every personality over 50k hands (CI > 0); distributions sum to 1 and are legal for random contexts; style sanity (Grumli VPIP 50–60%, Vexa 12–16%) | `sim` |
| Adaptive AI | vs scripted leaky user-simulators (over-folder, station, never-bluffer), Morwen's bb/100 after 2k hands beats non-adaptive Oryn's by ≥ 5 bb/100; vs a balanced simulator she does not lose more than 2 bb/100 compared with Oryn | `sim` |
| Analysis | hand-built spots with known EV (pot-odds calls, river value bets vs a known range); grade stability across seeds ≥ 95%; luck sums to zero in expectation over 50k sims | `unit`, `sim` |
| Solver (M10) | Kuhn value −1/18 ±0.001; Leduc exploitability < 0.01; blueprint file round-trip; resolver matches a brute-force solve on toy rivers | `heavy` |
| Curriculum | `ContentTests`: validator over all content (500 instances per template); FSRS vectors from Kata; skill update monotonicity; scheduler order | `content` |
| Themes | every shipped pack validates; `CodeDrawn.default` covers every `AssetSlot` case (exhaustive switch plus test); card renderer output is non-empty and deterministic (hash) for all 52 cards and backs | `unit` |
| Store | in-memory container CRUD; export → import round-trip equality; migration test from each previous schema | `unit` |
| UI | XCUITest smoke test per screen through demo launch (`-AllInDemo YES -AllInScreen <id> -AllInSeed 7`) that asserts key accessibility identifiers; keyboard shortcuts at the table; `Tools/screens.sh` captures a PNG of every screen into `build/screens/` for visual review | `ui`, `screens` |

### `Tools/test.sh` levels

| Level | What it runs | Time |
|---|---|---|
| `unit` | `swift test --package-path Packages/AllInKit --skip Heavy --skip Sim` | < 2 min |
| `heavy` | `swift test -c release --filter Heavy` | < 10 min |
| `sim` | `swift test -c release --filter Sim` | < 10 min |
| `content` | `--filter ContentTests` | |
| `lint` | swift-format lint, plus a grep that forbids UI imports in engine modules | |
| `ui` | `xcodebuild test -scheme AllIn -only-testing:AllInUITests` | |
| `all` | everything | |

`Tools/build.sh` runs `content validate`, then `theme validate`, then `xcodebuild -scheme AllIn -configuration Debug build`.

### What Haiku runs at the end of each milestone

| Milestone | Haiku runs | Also checks |
|---|---|---|
| M0 | `build.sh`, `test.sh unit`, `run.sh` | app launches; entitlements via `codesign -d --entitlements -` show the sandbox and no network |
| M1 | `unit`, `heavy` | evaluator counts; property tests |
| M2 | `unit`, `heavy`, `sim`, `allin-tool sim --games 2000` | bot style stats printed and within bands |
| M3 | `unit`, `build.sh`, `ui`, `screens.sh menu lobby table` | screenshots compared with wireframe screens 1, 6 and 10 (element checklist) |
| M4 | all except `content` | review screen screenshot; grading golden spots |
| M5 | all | lesson, sandbox, map and venue screenshots |
| M6 | all, plus a scripted full Tavern playthrough with `-AllInAutoplay tavern` | boss and exam gates |
| M7 | all, plus the perf checklist and App Store checklist | v1 sign-off |

---

## 10. Milestones

Each task is sized for one Sonnet subagent. "Files" lists what the task owns; other tasks must not edit those files. **Parallel** names tasks that can run at the same time.

### M0: Skeleton and local build scripts

**Goal:** an empty but complete structure that builds, tests and launches.

| ID | Task | Files | Acceptance |
|---|---|---|---|
| M0.1 | Package skeleton: all v1 modules and test targets with placeholder types; Swift 6 mode; platforms macOS 26; executable `allin-tool` printing help | `Packages/AllInKit/Package.swift`, `Sources/*/Module.swift`, `Tests/*/SmokeTests.swift` | `swift test --package-path Packages/AllInKit` passes |
| M0.2 | Xcode project modeled on Kata's `KataMac` target: `AllIn` app plus `AllInUITests`, local package reference, synchronized groups, `Content/` and `Themes/` as folder resources, entitlements (sandbox, user-selected read-write), privacy manifest, Info.plist (category), placeholder `RootView` "ALL-IN" | `AllIn.xcodeproj`, `AllIn/App/*`, `AllIn/Resources/*`, `Config/Info.plist`, `AllInUITests/LaunchTests.swift` | `xcodebuild build` passes; UI launch test passes; entitlements check |
| M0.3 | Scripts and docs: `Tools/build.sh`, `test.sh` (levels), `run.sh`, `screens.sh` (screencapture of the app window per demo screen), `.gitignore`, `.swift-format`, `docs/ARCHITECTURE.md` (§1 rules), `CONTRIBUTING.md`, README status | `Tools/*`, `docs/ARCHITECTURE.md`, root files | scripts run; `test.sh lint` passes |

**Parallel:** M0.1 and M0.3, then M0.2.
**Exit:** Haiku M0 checks are green.

### M1: Rules engine (PokerCore)

**Goal:** a complete, proven NLHE reducer and evaluator.

| ID | Task | Files | Acceptance |
|---|---|---|---|
| M1.1 | Cards, `CardSet`, `Deck`, parsing, `SeededRNG` | `PokerCore/Cards/*` | unit tests |
| M1.2 | Evaluator: `NaiveEvaluator`, table generator, `HandEvaluator`, `HandValue`, `bestFive`, `HandDescription` | `PokerCore/Evaluator/*`, `Tests/HeavyTests/EvaluatorEnumerationTests.swift` | golden + heavy enumeration counts + speed |
| M1.3 | `TableConfig`, `Action`, `LegalActions`, betting round rules | `PokerCore/Rules/*` | unit cases from §9 |
| M1.4 | `PotCalculator`, `PotDistributor` | `PokerCore/Pots/*` | brute-force comparison |
| M1.5 | `HandState`, `HandReducer` (start → award, all-in runout, showdown order) | `PokerCore/Hand/*` | scripted hands match expected stacks |
| M1.6 | `GameEvent`, `LoggedEvent`, `Visibility`, `EventLog.filtered(for:)`, `HandReplayer`, `HandHistoryFormatter` (text) | `PokerCore/Events/*` | replay equality; no-leak test |
| M1.7 | `StrategyProvider`, `DecisionContext`, `ActionDistribution`; random-playout property tests | `PokerCore/Strategy/*`, `Tests/PokerCoreTests/Property*` | 10k (unit) and 100k (heavy) hands, invariants hold |

**Parallel:** M1.1, M1.3, M1.4 together; then M1.2; then M1.5; then M1.6 and M1.7.
**Exit:** `unit` and `heavy` green.

### M2: Host, equity and personality bots (headless poker)

**Goal:** bots play complete cash sessions in the CLI.

| ID | Task | Files | Acceptance |
|---|---|---|---|
| M2.1 | `Seat`, `DecisionRequest`, `GameHost` actor, `BotSeat`, `ScriptedSeat`, `RandomSeat`, timeouts | `PokerHost/*` | host tests |
| M2.2 | `CashSession`: hand loop, button, top-ups, bust/sit-out, spectator stream | `PokerHost/Cash/*` | 1k-hand session conserves chips across hands |
| M2.3 | `HandRange`, `HandClass`, grid, parser/formatter, preflop ordering | `PokerEquity/Range/*` | round-trip and parsing tests |
| M2.4 | `EquityCalculator` (exact, Monte Carlo, progressive stream) | `PokerEquity/Equity/*` | golden and convergence tests, timing targets |
| M2.5 | `BoardAnalyzer`, `HandFeatures` (made class, draws, outs, nuts, beats-me list) | `PokerEquity/Board/*` | golden boards |
| M2.6 | `allin-tool gen-preflop` and `PreflopEquityTable` resource | `allin-tool/GenPreflop.swift`, `PokerEquity/Resources/preflop169.bin` | table matches exact enumeration for 20 sampled pairs |
| M2.7 | `PersonalityParams`, `PersonalityStrategy`; character JSON for 5 rivals, Bram, patrons | `PokerAI/Personality/*`, `Content/characters/*.json` | distribution validity tests |
| M2.8 | `BaselineStrategy` (Oryn) and `allin-tool gen-preflop-ranges` | `PokerAI/Baseline/*` | sim gates |
| M2.9 | `allin-tool sim` (matchups, bb/100 with CI, style stats) and Sim tests | `allin-tool/Sim.swift`, `Tests/SimTests/*` | §9 bot gates |

**Parallel:** M2.1 and M2.3 together; then M2.2, M2.4, M2.5 together; M2.6 after M2.4; M2.7 and M2.8 after M2.5; M2.9 last.
**Exit:** `sim` green; the printed style stats are within their bands.

### M3: Theme system and table UI (first playable)

**Goal:** play cash 6-max and heads-up against bots on the animated fantasy table.

| ID | Task | Files | Acceptance |
|---|---|---|---|
| M3.1 | ThemeKit: manifest, `AssetSlot`, loader, resolver chain, validator; `allin-tool theme validate`; `Themes/hearthwood.allintheme` | `ThemeKit/*`, `Themes/hearthwood.allintheme/*` | fixture tests; exhaustive fallback test |
| M3.2 | `CardRenderer` (faces, courts, backs, four-color) and `CardTextureCache` | `TableKit/Render/Card*` | determinism and non-empty tests; preview PNG dump via `allin-tool theme render-cards` |
| M3.3 | `TableRenderer` (rail, felt), `runes.fsh`, `ChipRenderer`, `ChipStackBuilder` | `TableKit/Render/Table*`, `Chip*`, `Shaders/*` | denomination tests; preview dump |
| M3.4 | `SoundBank` (procedural SFX, file slots, volume settings) | `TableKit/Audio/*` | sounds are generated; mute works |
| M3.5 | `TableScene`, `SeatLayout` (2/6/9), nodes, `AnimationQueue` (event → animations), speed scaling, reduce motion, scene modes | `TableKit/Scene/*` | headless test that queues a full logged hand and completes it; demo host |
| M3.6 | AllInUI design system: palette from theme, `FantasyButton`, `ParchmentPanel`, `Tag`, `Meter`, `AvatarMedallion`, `StarRow`, `CardView`, fonts | `AllInUI/DesignSystem/*` | preview catalog view in DEBUG |
| M3.7 | App shell: `AppRouter`, `Screen` enum, transitions, `DebugLaunch` (demo, screen, seed, content path), `Commands` | `AllIn/App/*` | UI smoke test navigates the menu |
| M3.8 | Table screen: `TableController` (host bridge, `LocalHumanSeat`), `ActionBar` (presets, slider, keyboard), top bar, basic HUD | `AllIn/Features/Table/*` | UI test plays 3 hands with the keyboard |
| M3.9 | Main menu (v1, animated `MenuBackgroundScene`, Today card placeholder) and Quick Play lobby (6-max/HU enabled, others disabled; opponents; options) | `AllIn/Features/Menu/*`, `Lobby/*`, `TableKit/Scene/MenuBackgroundScene.swift` | screenshots match screens 1 and 10 |

**Parallel:** M3.1 first; then M3.2, M3.3, M3.4, M3.6, M3.7 together; M3.5 after M3.2 and M3.3; M3.8 after M3.5 and M3.6; M3.9 after M3.6 and M3.7.
**Exit:** a human can play a 6-max or HU session; 120 fps holds in a quick Instruments check; the screens match the wireframe.

### M4: Analysis, coach panel, hand review, persistence

**Goal:** every hand is graded and reviewable; progress is saved.

| ID | Task | Files | Acceptance |
|---|---|---|---|
| M4.1 | `RangeTracker` | `PokerAI/Ranges/*` | Bayesian update tests on scripted bot lines |
| M4.2 | `ActionEVEstimator`, `ClosedFormEV` | `PokerAnalysis/EV/*` | known-EV spots |
| M4.3 | `DecisionGrader`, `SessionScorer`, `LuckCalculator`, `LeakDetector`, `PlayerStats` | `PokerAnalysis/Grading/*`, `Stats/*` | stability and luck tests |
| M4.4 | AllInStore SchemaV1, `ProgressStore`, `HandArchive`, `SaveFile` | `AllInStore/*` | in-memory and round-trip tests |
| M4.5 | Hand review screen: timeline, replay (scene `.replay`), EV chart, actions | `AllIn/Features/Review/*` | screenshot matches screen 7; UI test |
| M4.6 | Coach panel: three questions, "Show her range" (`RangeGridView` overlay from `RangeTracker`), "I'm fine"; stub hint level | `AllIn/Features/Coach/*`, `AllInUI/Range/RangeGridView.swift` | UI test toggles the panel |

**Parallel:** M4.1 → M4.2 → M4.3 in order; M4.4 in parallel; M4.5 after M4.3 and M4.4; M4.6 after M4.1.
**Exit:** review shows correct grades for scripted golden hands.

### M5: Curriculum engine and lesson UI

**Goal:** any lesson in JSON can be played end to end.

| ID | Task | Files | Acceptance |
|---|---|---|---|
| M5.1 | Content model and `ContentLibrary` loader (venues, nodes, lessons, templates, characters, skills) | `Curriculum/Model/*`, `Loading/*` | fixture pack loads; errors are descriptive |
| M5.2 | `SpotGenerator`: predicates, sampler, action-prefix builder, variation, fingerprints | `Curriculum/Generation/*` | 1k instances per fixture template are legal and satisfy constraints |
| M5.3 | `SpotEvaluator` (all methods) and `TextBinder` | `Curriculum/Evaluation/*` | golden answers |
| M5.4 | `SkillModel`, meters, FSRS port, `DrillScheduler`, `CoachEngine` (hint fading) | `Curriculum/Skills/*`, `SRS/*`, `Coach/*` | Kata FSRS vectors; ordering tests |
| M5.5 | `allin-tool content validate/preview/stats`; `ContentTests` | `allin-tool/Content*.swift`, `Tests/ContentTests/*` | the bad-fixture suite fails with the expected messages |
| M5.6 | Lesson player: hook, puzzle (scene `.spot`, coach box, hint −1★, step progress) and apply steps | `AllIn/Features/Lesson/LessonScreen*`, `LessonController.swift` | screenshot matches screen 4 |
| M5.7 | Explain + sandbox screen and the Tavern explainers (`BettingRoundsTimeline`, `HandRankLadder`, `BestFiveHighlight`, `PotCounter`, `BoardNutsScan`, `WhoCallsMe`) plus `PotSlices` and `OutsGlow`; `CardPickerView`; live `EquityBars` | `AllIn/Features/Lesson/Sandbox*`, `AllInUI/Explainers/*` | screenshot matches screen 5; bars update < 16 ms first frame |
| M5.8 | Career map and venue chapter screens | `AllIn/Features/Career/*`, `Venue/*` | screenshots match screens 2 and 3 |

**Parallel:** M5.1 first; then M5.2 and M5.4; M5.3 after M5.2; M5.5 after M5.3; the UI tasks M5.6–M5.8 after M5.1 using fixture content.
**Exit:** the fixture lesson can be played through all five steps; `content` green.

### M6: Village Tavern content, Gym, boss and exam

**Goal:** the Tavern can be fully played and cleared.

| ID | Task | Files | Acceptance |
|---|---|---|---|
| M6.1 | Tavern content A: `skills.json`, `venue.json`, nodes 1–4 (lessons, drill, templates) | `Content/skills.json`, `Content/venues/tavern/{venue.json,lessons/l1–l4,spots/*,drills/d1}` | validator green; preview reviewed |
| M6.2 | Tavern content B: nodes 5–10, table session, `boss.json`, `exam.json`, `reasons.json` seed | `Content/venues/tavern/...` (remaining files) | validator green |
| M6.3 | Gym: drill runner (fast reps, combo, timer), Smart mix, saved mistakes, locked drills | `AllIn/Features/Gym/*` | screenshot matches screen 12 |
| M6.4 | Boss intro screen; boss session rules (HU, N hands, no coach, minimum decisions); exam runner | `AllIn/Features/Boss/*`, `Curriculum/Gates/*` | gate unit tests; UI test |
| M6.5 | Venue result: stars, stamp, rewards (unlock theme variants), map unlock animation | `AllIn/Features/Result/*` | screenshot matches screen 9 |
| M6.6 | `NextActionPlanner` (Continue button), Today card, streak | `Curriculum/Planning/*`, `AllIn/Features/Menu/TodayCard.swift` | planner tests |
| M6.7 | Coach wired to real meters and hint fading in lessons and table sessions | `AllIn/Features/Coach/*` | tests at the meter thresholds |

**Parallel:** M6.1, M6.2, M6.3, M6.4 together; M6.5 after M6.4; M6.6 after M6.3; M6.7 last.
**Exit:** the autoplay run clears the Tavern with a scripted strong player and fails with a weak one; the owner plays it once.

### M7: The Arena (adaptive AI), remaining v1 screens, polish = **v1**

| ID | Task | Files | Acceptance |
|---|---|---|---|
| M7.1 | `PlayerModel` (keys, Beta counts, back-off, decay, showdown evidence, Codable) | `PokerAI/Modeling/*` | update and decay tests |
| M7.2 | `ExploitStrategy` (user range inference, best response, blending, `ExploitReason`) | `PokerAI/Exploit/*` | unit tests |
| M7.3 | Leaky user-simulators and adaptive Sim gates | `Tests/SimTests/Adaptive*` | §9 gates |
| M7.4 | Arena UI: hub, "What Morwen learned", arena table overlay, duel summary | `AllIn/Features/Arena/*` | screenshots A1, A2, A3, A5 |
| M7.5 | Rivals screen (discovered stats, notes, auto-notes, HU vs rival) | `AllIn/Features/Rivals/*` | screenshot matches screen 13 |
| M7.6 | My Game (radar, leaks → Gym, decision score vs chips chart, journal, hand history list) | `AllIn/Features/MyGame/*` | screenshot matches screen 14 |
| M7.7 | Settings (all sections, theme picker, export/import, shortcuts) | `AllIn/Features/Settings/*` | screenshot matches screen 15; round-trip UI test |
| M7.8 | Polish: Instruments perf pass, reduce-motion audit, VoiceOver labels ("Ace of hearts"), app icon (`Tools/make_app_icon.swift`), App Store checklist in `docs/RELEASE.md` | various, coordinated | perf and App Store checklists |

**Parallel:** M7.1 → M7.2 → M7.3 in order; M7.5, M7.6, M7.7 in parallel with them; M7.4 after M7.2; M7.8 last.
**v1 exit:** all tests green; 14 of 15 wireframe screens done (the tournament table comes later) plus Arena A1–A3 and A5; the owner can learn the Tavern, play Quick Play 6-max and HU, and duel Morwen.

### Post-v1 milestones

| M | Goal | Main tasks (one subagent each) |
|---|---|---|
| **M8** Guild Hall + Full Ring | venue 2 and 9-max | explainers (`PotSlices`/`OutsGlow` extended, `PositionWheel`, `CbetBoardMatrix`); content A and B (position, starting hands, pot odds, outs, c-bets); Grumli boss and exam; Gym drills (open or fold by seat, count the outs, call or fold pot odds, range painter, which hand wins v2); 9-seat layout tuning; full ring in the lobby |
| **M9** Tournaments | Sit & Go and MTT, 27–180 players | `TournamentDirector` (levels by time with pause on inactive, BB ante, dead button, table balancing and breaking, other tables simulated in the background with fast bots); ICM (Malmuth-Harville exact ≤ 10 paid, Monte Carlo ICM beyond); push/fold Nash tables (`allin-tool gen-pushfold`); tournament table screen (screen 11) and standings; bubble coach; push/fold drill |
| **M10** Near-GTO HU (Ysolde) | blueprint in the Arena | M10.1 Solver core with Kuhn/Leduc gates; M10.2 `PokerAbstraction` (isomorphism indexer, EMD k-means bucketing tool, action translation); M10.3 sizing spike and decision on the shipped size; M10.4 HU NLHE training run plus `.allinbp` export; M10.5 `BlueprintStrategy` runtime (mmap); M10.6 `RiverResolver`; M10.7 quality gates and `docs/AI_REPORT.md`; M10.8 Arena Ysolde card and intro |
| **M11** Seeing Stone advisor | sparring | `Advisor`, `ReasonBuilder` and `Content/reasons.json`; overlay UI (A4); assisted flag through stats |
| **M12** Royal Keep | venue 3 | explainers (`RangeVsRange`, `EquityDistribution`, `SizingStory`, `MultiStreetPlan`, `ICMPicture`); content in 3 parts; Sir Cedric boss and exam; drills (bet size: what does it say?, range painter v2, ICM spots) |
| **M13** Dragon's Hoard + strong multiway AI | venue 4 | 6-max/9-max preflop solve plus HU postflop mapping; content (balance vs exploit, bluff ratios, deep stacks, final tables, mental game, including tilt and session discipline); Ysolde as boss |
| **M14** Art and release | illustrated pack and submission | `illustrated.allintheme` drop-in (art from the owner or a commissioned artist), with validator gates; music slots; screenshots; App Store submission |

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| Hand-written pbxproj breaks | copy Kata's working structure; one task owns the project file; synchronized groups mean adding files needs no project edits |
| EV grading is biased by the continuation policy | close-spot rule, tolerances, stability tests; lesson spots prefer closed-form evaluation |
| Content volume is the bottleneck | templates generate many spots; the validator and preview make authoring cheap; each venue split into 2–3 content tasks |
| Solver compute or size larger than estimated | sizing spike M10.3 before training; fall back to coarser buckets or a 100 bb-only blueprint |
| SwiftUI over SpriteKit performance | overlays kept light; atlases; Instruments in M3 and M7 |
| Monte Carlo makes tests flaky | everything seeded; tolerances in σ; heavy tests run in release only |

## 12. Owner decisions (2026-11-04)

1. **Sound:** procedural SFX plus CC0 sample packs (for example Kenney's casino and RPG audio) in the default theme. Record each pack's source and license in `Themes/hearthwood.allintheme/CREDITS.md`.
2. **Blueprint size:** Ysolde's blueprint may add up to 500 MB to the app bundle.
3. **License and art:** MIT for everything, code and art, all in this public repo.
4. **Minimum macOS:** 26.0.

---

### Critical Files for Implementation

- `design/wireframes/index.html` (the approved UI; every screen task is checked against it)
- `Packages/AllInKit/Package.swift` (module graph and boundaries, created in M0.1)
- `Packages/AllInKit/Sources/PokerCore/Hand/HandReducer.swift` (the authoritative rules reducer, M1.5)
- `Packages/AllInKit/Sources/PokerHost/GameHost.swift` (Seat protocol and event-sourced host, M2.1)
- `Packages/AllInKit/Sources/Curriculum/Generation/SpotGenerator.swift` (anti-memorization spot generation, M5.2)
- Reference for M0.2: `../Kata/Kata.xcodeproj/project.pbxproj` (KataMac target)
- Reference for the M5.4 FSRS port: `../Kata/Packages/KataKit/Sources/KataSRS/FSRSScheduler.swift`
