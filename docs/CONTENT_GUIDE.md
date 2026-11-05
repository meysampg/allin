# Content guide

How to write the All-In curriculum: a content root is a folder of JSON files that the app and `allin-tool` load. This guide is enough to author a lesson from scratch.

## 1. Layout

A content root is a directory with a `realm.json`:

```
realm.json  skills.json  characters/ (optional)
venues/<venueID>/venue.json  lessons/*.json  spots/*.json  drills/*.json  boss.json  exam.json
```

- The real root is `Content/`. While it has no `realm.json` the app and the tool fall back to the fixture pack `Content/fixtures/sample`. Characters always come from `Content/characters`.
- Every file has `"schemaVersion": 1`.
- Unknown keys are errors. Files that are not `*.json`, and other files in the root, are ignored.
- A venue folder is named exactly like the venue id.
- Ids match `^[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+(-[a-z0-9]+)*)*$` (for example `fx.tavern.l4.pot-odds`) and are unique per kind.
- **ID stability.** Once released, an id never changes. Progress, spaced repetition and stars are stored by id. To retire a lesson or template, leave it in place (or add a new id and stop referencing the old one). Renaming an id resets every player's progress for it.

## 2. File kinds

Defaults are marked `= value`. All numbers in "ranges" are written `[lo, hi]` or as one number.

### realm.json

```json
{ "schemaVersion": 1,
  "venues": [
    { "id": "fx.tavern", "name": "Village Tavern", "icon": "village", "status": "open",
      "teaches": "rules, hand ranks, betting rounds" },
    { "id": "fx.guild", "name": "Guild Hall", "icon": "townHall", "status": "comingSoon",
      "teaches": "position, pot odds", "unlock": { "afterVenue": "fx.tavern" }, "lockedText": "beat the Tavern boss" } ] }
```

`icon`: `village|townHall|castle|cave`. `status`: `open|comingSoon`. An open venue needs `venues/<id>/venue.json`. `unlock.afterVenue` names the venue whose boss must be beaten first.

### skills.json

```json
{ "schemaVersion": 1,
  "axes": [ {"id": "math", "name": "Math"} ],
  "skills": [ { "id": "math.pot-odds", "name": "Pot odds", "axes": { "math": 1.0 }, "baseDifficulty": 0.4 } ] }
```

Axes used by the radar chart: `rules position math ranges sizing reading tournaments mental`. A skill weighs one or more axes. A skill that no content uses is a warning (`skill.unused`).

### venues/<id>/venue.json

```json
{ "schemaVersion": 1, "id": "fx.tavern", "name": "Village Tavern", "place": "The Gilded Tankard",
  "chapter": "Chapter 1: learning the table",
  "host": { "name": "Marta the Innkeeper", "line": "Pull up a stool, traveler.", "artKey": "marta" },
  "meters": [ { "id": "fx.tavern.rules", "name": "Rules & flow", "skills": ["rules.flow", "rules.actions"] } ],
  "nodes": [
    { "id": "fx.tavern.n1", "kind": "lesson", "lesson": "fx.tavern.l1.four-rounds" },
    { "id": "fx.tavern.n3", "kind": "drill", "drill": "fx.tavern.d1.which-wins" },
    { "id": "fx.tavern.n6", "kind": "table", "title": "Tavern night",
      "table": { "format": "cash6", "opponents": ["bram","patron","patron","patron","patron"], "hands": 40,
                 "blinds": "1/2", "stackBB": 100, "coach": "questions" } },
    { "id": "fx.tavern.n7", "kind": "boss", "boss": "fx.tavern.boss", "unlock": { "after": ["fx.tavern.n6"] } } ] }
```

- `kind` is `lesson|drill|table|boss` and the node carries exactly the matching field (`lesson`, `drill`, `table`, `boss`).
- `title` is optional; it defaults to the title of the lesson, drill or boss.
- `unlock.after` defaults to the previous node; the first node has `[]`. See "Unlock rules".
- Table `format`: `cash6` (5 opponents) or `headsUp` (1). `coach`: `questions|review|off`. `blinds`: `"S/B"` or `"S/B/ante"`. `opponents` are character ids; `patron` is the generic bot.

### spots/*.json (spot templates)

A template describes a family of spots; the engine deals a new one from each seed.

```json
{ "schemaVersion": 1, "id": "fx.potodds.flush-draw", "skill": "math.pot-odds", "difficulty": 0.4,
  "table": { "players": 2, "stacksBB": [60, 120], "blinds": "5/10" },
  "hero": { "position": "BB", "hand": { "draws": ["flushDraw"], "madeHand": ["noPair", "bottomPair"] } },
  "villain": { "character": "vexa", "position": "BTN" },
  "line": { "preflop": ["villain:open:2.5", "hero:call"], "flop": ["hero:check", "villain:bet:0.5-0.75"] },
  "board": { "street": "flop", "require": ["twoTone"] },
  "question": { "type": "action", "options": ["fold", "call", "raise:3"] },
  "evaluation": { "method": "closedFormEV", "vsRange": "tracked" },
  "quality": { "minGapBB": 0.2, "answerBalance": { "call": [0.4, 0.95] } },
  "prompt": "{villain} bets {bet}. Is this call worth it?",
  "hint": "You pay {toCall} to win {potIfCall}: you need {priceNeeded}. Your chance is about {equity}.",
  "explain": [ { "explainer": "potSlices" }, { "explainer": "outsGlow" } ],
  "variation": ["seats", "stacks"] }
```

Keys:

| key | meaning |
|---|---|
| `id, skill, difficulty` | `difficulty` is 0...1 |
| `table` | `players` 2...9, `stacksBB` range or number, `blinds`, optional `fillerNames` for seats nobody plays |
| `hero` | `position` (a name or a list), `hand` (a hand predicate) |
| `villain` / `villains` | `character` or `characters`, `names`, `position`, `hand`. Use one of `villain` or `villains` |
| `fixed` | `hero: "AhKh"`, `villains: ["QsQd"]`, `board: "Ks9h4h"` pin exact cards |
| `line` | betting history before the question (see "Line grammar") |
| `board` | `street`, `require`/`exclude` texture tags, `highCard` (for example `["A","K"]`) |
| `situation` | `facingBet`, `heroInPosition`, `spr` range |
| `potBB` | range for the pot, in big blinds, at the decision |
| `question` | `type`, `options`, `tolerance` (number questions), `pick` (cards to select) |
| `evaluation` | `method`, `ask`, `buckets`, `vsRange`, `target`, `equitySamples` |
| `quality` | `minGapBB`, `answerBalance`, `maxRetries = 4` |
| `prompt, coach, hint` | text with `{placeholders}` |
| `explain` | explainers shown after the answer |
| `variation` | which parts may vary: `suits seats stacks villainName` |
| `reveal` | `hero` (default) or `all` (show every involved hand) |

Positions: `BTN SB BB UTG UTG+1 UTG+2 LJ HJ CO`; only the names that exist at the table size are valid (`template.position` otherwise).

Hand predicates (`hero.hand`, `villain.hand`), all keys optional and combined with AND:

- `madeHand`: `noPair underPair bottomPair middlePair topPair topPairWeakKicker topPairGoodKicker overpair twoPair trips set straight flush fullHouse quads`
- `bucket`: strength bucket names; `draws`: `none flushDraw nutFlushDraw openEnded gutshot combo backdoorFlush anyDraw`
- `categories`: `highCard pair twoPair trips straight flush fullHouse quads straightFlush`
- `range`: range text such as `"22+,ATs+"`; `pocketPair`, `suited`: booleans; `outs`: `[lo, hi]`

Texture tags (`board.require`, `board.exclude`): `paired unpaired trips monotone twoTone rainbow flushPossible flushDrawPossible straightPossible connected dry wet`.

### Line grammar

`line` is the string `"checkThrough"` (everyone checks to the question) or an object:

```json
{ "preflop": ["villain:open:2.5", "hero:call"], "flop": ["hero:check", "villain:bet:0.5-0.75"],
  "turn": [], "river": [], "random": { "actions": [1, 9] }, "stopAt": "hero", "consistent": true }
```

- `preflop|flop|turn|river`: lists of tokens, played in order. `random: {actions: [lo, hi]}` instead plays a random legal line of that many actions.
- `stopAt`: `hero` (default), `villain` or `any`: who is to act when the line ends.
- `consistent` (default true) keeps the generated line coherent (no action that contradicts the earlier ones).
- A token is `[role:]act`. Roles: `hero villain villain2 villain3`. Acts: `fold check call limp allin any bet:F bet:F-G raise:X open:B`.
  - `F`, `G`: pot fractions in (0, 3]; `X`: a multiple of the current bet, at least 2; `B`: big blinds, at least 2 (preflop only).
  - `bet:0.5-0.75` picks a size in the range; `any` lets the generator choose a legal action.

### Method and question types

| method | question.type | street | notes |
|---|---|---|---|
| `showdownWinner` | `pickWinner` | river | all involved hands are shown; at least 2 involved seats |
| `bestFive` | `pickCards` (`pick: 5`) | turn, river | |
| `nuts` | `pickCards` (`pick: 2`), `pickHandClass` | flop+ | `pickHandClass` options are hand categories (default all) |
| `outs` | `pickCards`, `number` | flop, turn | |
| `beatsMeCount` | `choice` (options are bucket ids), `number` | flop+ | default buckets: `none [0,0]`, `few [1,20]`, `many [21,1326]`; override with `evaluation.buckets` `[{id,label,range}]` |
| `potCount` | `number` | any | `tolerance` defaults to 0 |
| `legalSizes` | `number` (`ask: callCost`), `sizeChoice` (`minRaise`), `choice` (`actions`) | any | `evaluation.ask` is required |
| `nextToAct` | `choice` | any | |
| `closedFormEV` | `action` | any | options `fold check call bet:F raise:X allin`; `vsRange` defaults to `"tracked"` (the range the villain's play implies) or range text |
| `policyEV` | `action` | any | every villain needs a `character` |
| `pushFold` | `action` (exactly `fold`, `allin`) | preflop | 2 players, villain character |
| `rangeMatch` | `rangePaint` | preflop | `stopAt: villain`; `target` defaults to `"policy"` or range text |

The EV methods (`closedFormEV`, `policyEV`, `pushFold`) grade by expected value in big blinds. The best option is correct; a close second is "acceptable". `quality.minGapBB` asks for a clear winner.

### Text and placeholders

`prompt`, `coach`, `hint` (templates) and the `coach`, `hint`, `thinking` and `challenge` text of lesson steps use `{name}` placeholders; write `{{` and `}}` for literal braces. A lesson step is bound by its own spot (for `explain` and `sandbox` steps, by the nearest earlier spot step).

Keys available for every method: `villain villainStyle villainPosition hero heroHand heroHandName position board street pot potBB potBeforeBet bet toCall potIfCall stack bigBlind players actor`.

Extra keys per method:

| method | extra keys |
|---|---|
| `closedFormEV`, `pushFold` | `priceNeeded equity evGain bestAction answer` |
| `policyEV` | `evGain bestAction answer` |
| `outs` | `outs outsCount` |
| `nuts` | `nuts` |
| `bestFive` | `bestHand` |
| `showdownWinner` | `winner winningHand` |
| `beatsMeCount` | `beatsMeCount` |
| `potCount`, `legalSizes`, `nextToAct`, `rangeMatch` | `answer` |

An unknown key is the error `placeholder.unresolved` ("unknown placeholder {villian}").

### Explainers

Explainer ids: `bettingRoundsTimeline handRankLadder bestFiveHighlight potCounter boardNutsScan whoCallsMe potSlices outsGlow`. Write one as `"potSlices"` or `{ "explainer": "whoCallsMe", "bind": {...}, "caption": "..." }`. Allowed `bind` keys (anything else is `lesson.explainer`):

| explainer | bind keys |
|---|---|
| `handRankLadder` | `highlight` (`hero` shows only the hero's category; default both) |
| `bestFiveHighlight` | `hand` (`hero` default, `villain`, `winner`) |
| `whoCallsMe` | `mode` (`callers` or `bettors`), `size` (for example `bet:0.5`), `range`, `hand` |
| the others | none |

### lessons/*.json

```json
{ "schemaVersion": 1, "id": "fx.tavern.l4.pot-odds", "title": "Pot odds: is the call worth it?",
  "skills": ["math.pot-odds"],
  "steps": [
    { "kind": "hook", "spot": "fx.potodds.obvious" },
    { "kind": "puzzle", "spot": "fx.potodds.flush-draw",
      "coach": "You have {heroHandName}. {villain} bets {bet} into {potBeforeBet}." },
    { "kind": "explain", "title": "Why calling works", "explainers": ["potSlices", "outsGlow"],
      "thinking": "Compare what you pay to what you can win." },
    { "kind": "sandbox", "title": "Alchemist's Bench", "controls": ["heroCards", "board", "villainBet"],
      "meters": ["priceNeeded", "yourChance"], "challenge": "Make {villain} bet the whole pot." },
    { "kind": "apply", "spot": "fx.potodds.flush-draw", "count": 3, "freshSeeds": true } ],
  "stars": { "hintCost": 1, "three": { "puzzleGood": true, "applyGood": 3 }, "two": { "applyGood": 2 } } }
```

- `hook`, `puzzle`: `{spot, coach?, hint?}`. `apply`: `{spot, count 1...10, freshSeeds = true, coach?}`. `explain`: `{title?, explainers, thinking?}`. `sandbox`: `{title?, controls, meters, explainer?, challenge?}`. A sandbox step needs an earlier hook or puzzle step.
- Sandbox controls: `heroCards board villainBet`. Sandbox meters: `priceNeeded yourChance worseThatCall betterThatCall potAfter outs bestFive nuts`.
- `stars.hintCost` (default 1) is what a hint costs; `three` and `two` are the rules for each star level (`puzzleGood`: the puzzle answered well; `applyGood`: how many apply spots answered well).

### drills/*.json

```json
{ "schemaVersion": 1, "id": "fx.tavern.d1.which-wins", "title": "Which hand wins?", "skills": ["ranks.compare"],
  "spots": [ { "template": "fx.ranks.pick-winner", "weight": 1 } ], "reps": 10, "timerSeconds": 8, "gym": true }
```

`weight = 1`, `gym = true` (the drill also shows up in the Gym), `timerSeconds` optional.

### boss.json and exam.json

```json
{ "schemaVersion": 1, "id": "fx.tavern.boss", "character": "bram", "title": "Bram Ironmug, Tavern Champion",
  "quote": "I only bet when I've got it.", "format": "headsUp", "hands": 30, "blinds": "1/2",
  "stackBB": 100, "coach": false, "minDecisions": 15, "minScore": 65,
  "requirements": ["Decision score 65 or more over 30 hands", "Pass the exam: 10 of 12"],
  "exam": "fx.tavern.exam", "stars": { "two": { "score": 75, "exam": 11 }, "three": { "score": 85, "exam": 12 } } }
```

```json
{ "schemaVersion": 1, "id": "fx.tavern.exam", "title": "Tavern exam", "count": 12, "pass": 10,
  "draw": [ { "template": "fx.rules.call-cost", "count": 2 }, { "template": "fx.ranks.pick-winner", "count": 2 } ] }
```

The draw counts must add up to `count` (`exam.count`), and `pass` may not exceed `count`.

### characters

Bot characters live in `Content/characters/<id>.json` and belong to the bot engine. The content only reads the presentational keys `title, artKey, bio, quote, howToBeat, names`.

## 3. Unlock rules

- A node unlocks when every node in its `unlock.after` is complete. Without `unlock`, it needs the previous node; the first node is always open.
- A venue unlocks when the boss of `unlock.afterVenue` is beaten.
- Cycles (`graph.cycle`) and nodes that can never unlock (`graph.unreachable`) are errors.
- A boss is beaten when the table session meets `minDecisions` and `minScore` and the exam is passed.

## 4. The authoring loop

1. Edit JSON under your content root.
2. `allin-tool content validate [--root DIR]` checks references, graphs, text and placeholders, then generates and solves every template (500 instances, 100 for EV templates; `--quick` is 100/20; `--template ID` narrows it; `--n` and `--ev-n` set the counts; `--seed` changes the seeds; `--budget test` uses cheap rollouts for a fast, noisier pass). It prints one line per template:
   `ok   fx.value.river-bet-or-check  500/500  check 52% bet 48%  gap 94%  p95 gen 3 ms eval 41 ms`
   Exit status 1 means errors.
3. `allin-tool content preview <template-id> --n 8 --seed 1 [--root DIR]` prints the generated spots (seed, hash, table, cards, line, prompt, answer and the EV list). The output is the same for the same seed, so you can quote a seed in a bug report.
4. `allin-tool content stats [--root DIR]` shows templates per skill, method and question type, a difficulty histogram and per-venue counts.
5. Run the app on your folder: `AllIn -AllInContent <dir>` (add `-AllInDemo YES -AllInScreen lesson` to jump to a lesson).

Without `--root`, the tool uses `Content/` when it has a `realm.json`, else the fixture pack. `Tools/build.sh` runs `content validate --quick` after the package builds. The `ContentTests` suite (`Tools/test.sh content`) validates the fixture pack and, once it exists, the shipped content.

Tuning a template that fails: `gen.exhausted` means the predicates are too tight (lower the requirements, widen `stacksBB`, drop an `exclude`); `gen.balance` means one answer is too common (widen the range or change the predicates that decide the answer); `gen.gap` means the best and second-best options are too close (change `potBB`, the sizes in `question.options`, or the line).

## 5. Issue codes

| code | meaning |
|---|---|
| `json.decode` | a file does not parse or has a wrong type, a missing key, a bad enum value or a bad line token (for example `bad line token 'bet:x' (expected bet:<fraction>)`) |
| `json.unknownKey` | a key the format does not know ("unknown key 'explainr'") |
| `schema.version` | `schemaVersion` is not 1 |
| `id.format`, `id.duplicate`, `venue.folder` | bad id syntax, an id used twice for a kind, a venue folder that differs from the venue id |
| `ref.unknown` | a reference to a lesson, template, drill, boss, exam, skill, character, node, axis or venue that does not exist |
| `graph.cycle`, `graph.unreachable`, `realm.missingVenue` | unlock cycles, nodes that can never unlock, an open venue without `venue.json` |
| `template.methodQuestion` | the method cannot answer that question type, or a required key is missing |
| `template.street`, `template.position`, `template.option`, `template.fixed`, `template.range`, `template.character` | street, position, option, fixed cards, range text or villain character does not fit the method |
| `lesson.steps`, `lesson.explainer` | a lesson structure problem (for example a sandbox step before any spot) or an unknown explainer bind key |
| `exam.count` | draws do not add up to `count`, or `pass` is above `count` |
| `table.opponents` | the number of opponents does not fit the format |
| `skill.unused` | warning: no content uses the skill |
| `placeholder.unresolved` | text uses a `{key}` the method does not provide |
| `gen.invalid` | the template cannot be generated at all (bad table, villains or fixed cards) |
| `gen.exhausted` | no instance could be built within 2000 tries |
| `gen.evaluate` | an instance was built but could not be solved |
| `gen.balance` | an answer class is outside its `answerBalance` range |
| `gen.gap` | fewer than 90% of instances have a gap of at least `minGapBB` |
| `gen.slow` | warning: p95 evaluation time above 50 ms (exact) or 500 ms (EV) |
