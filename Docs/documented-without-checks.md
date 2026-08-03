# Documented behaviour with no check behind it

An audit against the rule in `CLAUDE.md`: where a comment or `SPEC` states a
condition, a check must fail when that condition is broken. A comment without
a check is an intention, not a property.

The audit covers every doc comment on a public type, every enum case, and the
conditions stated in `SPEC` sections 2–8.

**First pass: 33 items, one of them a live defect. This pass: 5 remain**, and
none of the five can be closed by the kind of check the others were.

Three more have been added since — G4 and G5 by the hysteresis work in
`SPEC` 7, G6 by the one-grid rule for the age in `SPEC` 2.4. All three are
numbers or latencies rather than behaviour, and each names what stops a check
from existing. The behaviour they argued for is checked.

---

## What closed, and how

| Class | Items | Closed | Where |
|---|---:|---:|---|
| A. Which verdict, not which number | 6 | 6 | `ForecastTests` |
| B. Loud soft parsing | 6 | 6 | `DiagnosticsTests`, `HistoryTests` |
| C. The exporter | 8 | 8 | `ExporterTests` |
| D. History rules | 2 | 2 | `HistoryTests`, `ExporterTests` |
| E. Installer conditions | 6 | 6 | `InstallerConditionsTests`, `OutcomeCoverageTests` |
| F. Display rules | 2 | 1 | `PolarityTests` |
| **Total** | **30** | **29** | |

Plus the enum audit the rule implies: every case of every enum in the project
is now produced by a check that expects it, except the enum named below.
`SnapshotStoreError.containerUnavailable` was deleted rather than covered — no
code path threw it.

**A second sweep asked a stronger question**: not whether each case is
produced, but whether each case makes an observable difference *in what that
enum is responsible for*. Being produced is not enough — a case can be produced
and mean nothing. All thirteen enums were taken in turn, each with its own area
named first: the widget's appearance for `Freshness`, the message and the
suggested action for `Installer.Failure`, the verdict for `Forecast.Outcome`,
the diagnosis for `Forecast.Gate`. The guards live in
`ObservableDifferenceTests`, one per enum, each verified by planting a
collision and watching it fail.

The sweep produced all three of the outcomes it can produce, which is why it
was worth running:

| | |
|---|---|
| **Distinguishable** | eight enums; a guard each |
| **Indistinguishable, and the difference was not needed** | `Freshness` — `fresh` and `recent` drew the same; collapsed |
| **Indistinguishable, and the difference *was* needed** | `WindowState.abandoned` produced nothing, and should have withheld the numbers; `SettingsEditor.RemovalOutcome` did not report a rebuilt file where installation did. Both were missing behaviour, not surplus cases |

Two of the guards were unwritable until the thing they guard came out of a
view: the estimate block's caption, colour and chart, and the window's badge
and explanation. Both are now composed as values — `estimateStatement` and
`WindowState.badge`/`.explanation` — and rendered from them, the way
`gaugeAnnouncement` already was.

**A1 was a real defect.** `.runsOut` was documented as "exhaustion falls
before the reset" and implemented as "exhaustion falls inside the horizon", so
a quota that outlived its window was reported in red with a date after the
counter resets. Found by reading the comment against the code, reproduced from
live data, fixed after the check failed on it.

---

## What remains

### Not yet built: the rendering tiers

These are the plan in [`rendering-checks.md`](rendering-checks.md), agreed and
scheduled, not gaps in the audit's sense. Listed so nothing is lost.

**F2. No fixed widths for text.** `SPEC` 774 — *"Немецкий длиннее английского
примерно на треть."* This is tier 1, text metrics: measure every localized
caption with the font and the width the layout gives it. The clipped-footer
class of defect closes there.

**One enum of view state.** `OnboardingStep` decides which of four step views
the setup screen shows, and that consequence is a view — tier 2, the
accessibility-tree snapshots. Its transitions are checked; the distinctness of
what they render is not.

`WindowState` used to be listed here beside it. It left `StatusView` earlier,
and now its badge, tone, explanation and whether bars are drawn are values
rather than view code, so `windowStatesDiffer` covers all six cases. Getting
there is what exposed the missing `.abandoned` branch.

### Cannot be built: stated as unverifiable

Each is now marked in `SPEC` with **what specifically prevents a check**, so
the mark is a fact about the world rather than an apology.

**G1. The WidgetKit reload budget** — `SPEC` 2.3.
The remaining budget is published nowhere, and a refused reload is not
reported: the system simply does not call the provider. The only observable
consequence, the data's age, grows identically whether the budget is spent or
Claude Code is closed. A check becomes possible if Apple publishes either
figure.

**G2. Which branch computes the exchange path** — `SPEC` 2.2.
Both branches are covered separately: the parameterised `exchangeURL(home:)`
in `Tests/`, and the sandboxed behaviour observed on the live extension. The
choice itself — the `isSandboxed` predicate — is not, because it is derived from
the process environment and the test bundle does not run sandboxed. Faking the
predicate would check the fake: the branch would be chosen by something other
than what chooses it in production.

**G3. The widget on macOS 14 and 15** — `SPEC` 5.
WidgetKit draws only on a logged-in user's desktop, and a widget cannot be
placed there by any command or API — only by dragging it from the gallery. CI
images have no desktop session. Tier 3 covers the views' rendering; it does not
cover WidgetKit.

**G4. The flicker figures on real history** — `SPEC` 7, hysteresis.
Eight state changes becoming five, the dips at 0.648 and 0.653 against the one
at 0.507, the median R² of 0.710 — every one of them is measured on one
person's `history.jsonl`. That file is not in the repository and should not be:
it is a record of when its owner was working. `./.build/ccwidget-replay <file>`
re-derives the whole table from any such file in about a second, and CI builds
the tool so it cannot rot. What the checks cover is the behaviour the figures
argued for — the two thresholds, the latch, the lead times — in
`ForecastTests` and `EstimateProfilesTests`. What they cannot cover is the
figure itself, because the data is somebody's week.

**G5. What replaying the gate costs** — `SPEC` 7, hysteresis.
1.8 ms at 200 points, 26 ms at 1000, 98 ms at the two-thousand-line truncation
limit, measured in an optimised build on an Apple silicon laptop. A check here
would assert a wall-clock time on a shared runner whose speed nobody controls,
which is how a suite learns to fail for no reason. Stated as measured, with the
machine named, rather than checked.

**G6. The last few milliseconds of the age** — `SPEC` 2.4, one grid.
The window and the widget now measure the age from the same minute, and that
is checked character for character. What is not checked is the window's timer
firing exactly on the boundary: `Timer` may run late by whatever the run loop
is busy with. A check would have to observe a real timer against a real clock,
which is a test that fails on a loaded machine and passes on an idle one. The
gap is one-sided — a timer cannot fire early — so the window can lag the widget
by the latency and never lead it, and it is stated in `SPEC` rather than
measured.

---

## Method

The enum sweep is reproducible:

```sh
python3 - <<'PY'
import pathlib
tests = "".join(p.read_text() for p in pathlib.Path("Tests").glob("*.swift"))
# every case of every enum, against what the checks name
PY
```

It is a text search and therefore only as good as the checks' habit of naming
what they expect. That habit is worth keeping for its own sake: a check that
asserts `.lastsUntilReset` by name says what it is for, and one that asserts a
string comparison against a formatted description does not.
