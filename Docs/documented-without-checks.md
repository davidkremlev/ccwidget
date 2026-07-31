# Documented behaviour with no check behind it

An audit against the rule added to `CLAUDE.md`: where a comment or `SPEC`
states a condition, a check must fail when that condition is broken. A comment
without a check is an intention, not a property.

The audit covers every doc comment on a public type, every enum case, and the
conditions stated in `SPEC` sections 2–8. **Nothing here is fixed.** Each entry
names the documented claim, where it is written, and what a check would have to
do.

The defect that prompted this is item **A1**.

---

## A. Which verdict, not which number

The estimate has eighteen checks and all eighteen test the arithmetic. None
tests the verdict against the reset, which is where the defect lives.

**A1. `.runsOut` requires exhaustion before the reset.** ⚠️ **Confirmed defect**
`Shared/Forecast.swift:23` — *"Exhaustion falls before the reset and within the
horizon."* The code at line 170 branches on the horizon alone and never
compares `exhaustion` with `window.resetsAt`. Live numbers: 11 % used, reset in
140.6 h, exhaustion extrapolated to 156.2 h, horizon 274.1 h → `runsOut` at a
date fifteen hours *after* the counter resets to zero.
*Check:* a series whose exhaustion falls after the reset but inside the horizon
must yield `.lastsUntilReset`.

**A2. `.lastsUntilReset` is never produced by any check.**
`Shared/Forecast.swift:20`. The case exists in the enum and in `describe()`, and
no test asserts it. That is why A1 survived.
*Check:* the same series as A1, plus `showsProjection == true` and `hasRate ==
true`, both documented for this case.

**A3. `.flat` covers a falling slope, not only a level one.**
`Shared/Forecast.swift:14` — *"The slope is not positive."* The only check uses
a series with zero growth. A decreasing series — which happens after a
correction, or when the exporter writes a lower value — is untested.
*Check:* a descending series must be `.flat`, not `.runsOut` in the past.

**A4. The slope and R² survive a rejected fit.**
`Shared/Forecast.swift:149` — *"Keep the slope and R² anyway: without them the
dump tool cannot show why it refused."* `rejectsPoorFit` asserts the outcome
and nothing else.
*Check:* on a poor fit, `slope != nil && fitQuality != nil`.

**A5. `exhaustionAt` is kept even when it must not be shown.**
`Shared/Forecast.swift:33`. No check reads it outside `.runsOut`.
*Check:* `.rateOnly` still carries a non-nil `exhaustionAt`.

**A6. Recency weighting does anything at all.**
`Shared/Forecast.swift:58` — *"yesterday's marathon must not skew today's
estimate."* `weightHalfLife` appears in no check. An unweighted regression would
pass every existing test.
*Check:* two series with identical endpoints, differing only in an old burst,
must produce different slopes — and the weighted one must be closer to the
recent trend.

---

## B. The loud-soft-parse rule (SPEC 6.1)

The project's central rule — *"молчаливое проглатывание запрещено"* — has one
check, in the wrong place. `SecurityTests` exercises the history's symlink
refusal; nothing exercises the diagnostics.

**B1. A field absent is silent; a field present and unparseable is loud.**
`SPEC` 6.1 and `Shared/Snapshot.swift:100` — *"A missing `rate_limits` is
expected ... and stays silent; a corrupted window must reach the log and the
diagnostics."* This is stated as the single exception to the rule and has no
check either way.
*Check:* a snapshot with no `limits` key → `diagnostics.isEmpty`; a snapshot
with a malformed `limits` → exactly one entry naming that field.

**B2. `decodeSoft` records what it dropped.**
`Shared/Diagnostics.swift:87` — *"records it in the log and in the diagnostics
and returns nil. Nothing is swallowed quietly here."* No check.
*Check:* every softly-decoded field that fails appears in `diagnostics` with
its path and its raw value.

**B3. `diagnostics` is empty in the normal case.**
`Shared/Snapshot.swift:18`. No check. A parser that reported spurious issues on
good input would pass today.

**B4. A broken history line is skipped, never quietly.**
`Shared/HistoryStore.swift:34`. No check that a truncated last line is skipped,
and none that the skip is counted.

**B5. An unknown schema version is rejected.**
`Shared/Snapshot.swift:3` and `SnapshotStore.swift:141` — *"A snapshot with a
higher version is unusable"*, *"rejected — a dash beats drawing nonsense."* No
check.
*Check:* `schemaVersion: 2` must throw, not render.

**B6. Fractional percentages survive.**
`Shared/Snapshot.swift:121` — *"a live snapshot carried
`28.000000000000004`. Strict decoding lost the entire window over it."* This is
a historical defect with a comment and **no check**. `decodeRoundedInt` appears
nowhere in `Tests/`.
*Check:* `"used_percentage": 28.000000000000004` decodes to 28, and the window
is not dropped.

---

## C. The exporter's guarantees (SPEC 3)

Seven guarantees are listed in `SPEC` as properties of the exporter. **None has
a check.** CI compiles the template with `py_compile` and stops there. This is
the component that runs dozens of times a minute on the user's machine.

| Guarantee | `SPEC` | Check |
|---|---|---|
| Never writes through a symlink | 378 | none (the Swift-side history check is a different code path) |
| Reads at most one megabyte from stdin | 379 | none |
| Interpreter pinned to an absolute path | 380 | ✅ `InstallerTests` |
| Always exits with code 0 | 382 | none |
| Prints nothing to stdout | 383 | none |
| Writes atomically via `os.replace` | 384 | none |
| Missing fields are normal — no `KeyError` | 385 | none |

*Check:* these are testable from Swift by running the rendered exporter as a
subprocess with crafted stdin — empty input, garbage, a gigabyte, a payload
with every optional field missing — and asserting the exit code, the empty
stdout, and the resulting file.

**C1. The snapshot carries only what is displayed.**
`SPEC` 433 — *"Полного пути к проекту здесь нет намеренно."* No check. A future
edit re-adding `project.path` would pass everything.

---

## D. History rules (SPEC 7)

**D1. At most 2000 lines, truncated to the last 1000.**
`SPEC` 667 and `Shared/HistoryStore.swift:30`. `truncateIfNeeded` is called by
exactly one check, which is about symlinks. Neither number is asserted.
*Check:* 2500 lines → 1000 remain, and they are the last 1000; 1999 lines →
untouched.

**D2. Deduplication on write.**
`SPEC` 657–659 — a new line only if the reset changed, the percentage changed,
or ten minutes passed. Implemented in the exporter, no check.

---

## E. Installer conditions

**E1. The interpreter is probed, not assumed.**
`App/Installer.swift:190` — *"Running it is mandatory: on a clean macOS
`/usr/bin/python3` exists but is a stub."* `findInterpreter` appears nowhere in
`Tests/`. This is the one thing a clean account was going to test by hand.
*Check:* with injected candidates — one that does not exist, one that exits
non-zero, one that answers — the third is chosen.

**E2. The system Python comes first, deliberately.**
`App/Installer.swift:15` — a security rationale, no check on the order.

**E3. `~/.claude` is created closed, and an existing one is left alone.**
`App/Installer.swift:289` — *"We create the directory closed. We never touch
the permissions of one that already exists."* No check for either half. `0o700`
appears nowhere in `Tests/`.

**E4. A symlink whose target cannot be written.**
`App/Installer.swift:74` — `canPreserveLink` is documented as a distinct state
and has a localized string of its own. Only the writable case is checked.

**E5. `manualInstructions` survives a hostile path.**
`App/Installer.swift:463` — *"No `sed`: a path containing `|` breaks the
delimiter and one containing a quote breaks the literal."* No check, while the
equivalent property for the generated Python literal *is* checked.

**E6. Removing an absent key reports `.absent`.**
`App/SettingsEditor.swift:34`. No check.

---

## F. Display rules (SPEC 8)

Both are tier-1 and tier-2 work already agreed; listed so the audit is complete.

**F1. The bar always equals the number beside it.**
`SPEC` 704 and `Widget/Components.swift:21`. No check. This is the polarity
defect class.

**F2. No fixed widths for text.**
`SPEC` 774 — *"Немецкий длиннее английского примерно на треть."* No check; this
is the clipped-footer class.

---

## G. Stated as unverifiable

Named for completeness — these have no check and, as far as I can tell, cannot
have one here.

- **The WidgetKit budget** (`SPEC` 123) is already labelled an unverified
  assumption in `SPEC` itself. Nothing about it is observable from outside.
- **The sandbox path branch** (`Shared/SnapshotStore.swift:44`) — *"adding one
  path to the other doubles it."* `isSandboxed` is derived from the process
  environment, so a check would have to run inside a sandboxed process. The
  parameterised `exchangeURL(home:)` is checked; the branch that picks it is
  not.
- **The widget on macOS 14 and 15** — no desktop, no session, no way.

---

## Count

| Class | Items | Of them confirmed defects |
|---|---:|---:|
| A. Verdicts | 6 | 1 |
| B. Loud soft parse | 6 | 0 |
| C. Exporter | 8 | 0 |
| D. History | 2 | 0 |
| E. Installer | 6 | 0 |
| F. Display | 2 | 0 |
| G. Unverifiable | 3 | — |
| **Total** | **33** | **1** |

One is a live defect. The rest are conditions the code may well satisfy today —
the point is that nothing would notice if it stopped.
