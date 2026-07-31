# Documented behaviour with no check behind it

An audit against the rule in `CLAUDE.md`: where a comment or `SPEC` states a
condition, a check must fail when that condition is broken. A comment without
a check is an intention, not a property.

The audit covers every doc comment on a public type, every enum case, and the
conditions stated in `SPEC` sections 2–8.

**First pass: 33 items, one of them a live defect. This pass: 5 remain**, and
none of the five can be closed by the kind of check the others were.

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
is now produced by a check that expects it, except the two enums named below.
`SnapshotStoreError.containerUnavailable` was deleted rather than covered — no
code path threw it.

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

**Two enums of view state.** `StatusView.WindowState` (five of six cases) and
`OnboardingView.Step` (three of four) are private to their views and reachable
only through view-level checks — tier 2, the accessibility-tree snapshots.
`WindowState.abandoned` and `Step.install` happen to be named elsewhere; the
rest are not produced by anything.

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
