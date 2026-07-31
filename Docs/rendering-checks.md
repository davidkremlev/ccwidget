# Rendering checks: what to build, and what not to

The view code has no coverage at all — 2136 lines across nine files that no
check has ever executed. The screenshot tool already renders every size, both
appearances and all six languages, so image baselines committed to the
repository look like the obvious next step.

This is the analysis of whether they are. **Recommendation first: build three
things, and image baselines are the smallest of them.**

---

## The defects this is meant to catch

Four have actually happened here. They are not one class, and that turns out
to decide the whole question.

| # | Defect | Would a pixel baseline have caught it? |
|---|---|---|
| 1 | The estimate chart drew a stub in the "not enough data" state | **Yes**, and little else would have |
| 2 | The German and Russian footers ended in an ellipsis | Yes — but a targeted check names it instead of showing a red rectangle |
| 3 | The bar showed remaining while the number showed used | Only if a human noticed the diff was *wrong*; the property is assertable without rendering |
| 4 | VoiceOver read three rows as bare numbers, and detail rows as unrelated items | **No.** Nothing about it is visible |

Half of the history is not a rendering problem. That is the first argument
against making rendering the centre of the answer.

---

## Prerequisite: the tool is not deterministic, and the reason is not macOS

Measured, not assumed. Two runs of the current tool, seconds apart, same
machine, same locale:

```
small-light    identical
medium-light   0.364 % of pixels differ
large-light    0.175 % of pixels differ
```

The renderer is fine — the small tile came out byte for byte identical. What
moves is the *data*: the tool reads the live snapshot, and the countdown ticks
from `3 hr 59 min` to `3 hr 58 min` while the relative age goes from `3
seconds ago` to `6 seconds ago`. The small tile survived only because it shows
neither.

So the first piece of work is not baselines. It is **a fixture and a clock**:
the tool has to take its snapshot from a file in the repository and its "now"
from a constant. The code is already shaped for it — `Forecast.make` takes
`now:`, `CCWidgetEntry` takes `date:` — so this is plumbing, not redesign.

It pays for itself immediately regardless of what follows. The README
screenshots are currently whatever the developer's account happened to be
doing that afternoon, which is why CHANGELOG carries a note to re-shoot them
once the estimate has more history. With a fixture they show the state we
choose to show, every time.

---

## Why a tolerance threshold is the wrong knob

The instinct with cross-machine rendering is to allow N % difference. The
numbers say what that costs. Same two measurements, plus a real defect — the
German footer, reproduced by putting `lineLimit(1)` back:

| Change | Pixels differing |
|---|---|
| Six seconds of clock drift (medium) | **0.364 %** |
| Clipped German footer (small) | **9.009 %** |

A 25× gap, so a threshold looks workable. It is not, and the reason is in the
first row: 958 pixels moved because roughly two numbers changed. One digit is
therefore a few hundred pixels — and **a word replaced by an ellipsis is the
same order of magnitude.** The gross version of defect #2 is far above the
noise; the subtle version, one caption ending in `…` while everything else
fits, sits inside it.

A threshold loose enough to absorb data drift is loose enough to miss the
defect it exists for. The answer is to remove the noise, not to raise the
floor above it.

---

## Feasibility on the two-version matrix

**Unknown, and cheap to find out.** Nobody has measured whether `ImageRenderer`
produces the same pixels on macOS 14 and macOS 26. It should be assumed it
does not, because everything a widget is made of moves between releases: system
font metrics and hinting, the exact values behind `.green` / `.yellow` / `.red`,
SF Symbols shapes and their version numbering, text antialiasing, and the
default padding inside SwiftUI containers.

Step zero, whenever the repository exists: one CI job that renders the same
fixture on both runners and uploads both artifacts. One run answers it. Until
then this section is a prediction, and it should be labelled as one.

If the pixels do differ, there are three ways out and they are not equal:

**(a) A baseline set per OS version.** Doubles the files, and creates a
workflow problem that has nothing to do with size: *nobody owns a macOS 14
machine.* Regenerating that half means pushing a branch, waiting for CI,
downloading an artifact and committing it — on every intentional UI change.
That is a tax on the most ordinary kind of work in this project.

**(b) Baselines on the primary version only; non-image checks on the minimum.**
No cross-version problem, because there is no cross-version comparison. What
is given up is a signal we have never had and cannot get anyway: the widget
has never run on macOS 14 at all — WidgetKit needs a desktop and a session,
and CI has neither.

**(c) A perceptual tolerance.** Covered above. No.

---

## What the grid actually costs

The dimensions multiply, and this is where image baselines stop scaling:

| Grid | Images | Approx. size |
|---|---:|---:|
| 3 sizes × 2 appearances (today's README set) | 6 | 231 KB |
| + 6 languages | 36 | ≈ 1.4 MB |
| + 5 estimate outcomes (large size only) | 96 | ≈ 5 MB |

And every intentional change to a caption regenerates the whole language
column at once. Two of those have already happened — the display-name rename
and the row-caption rewrite — in a project that has not been published yet.
Each would have produced a 36-file diff that no reviewer reads, which is the
state in which a baseline set stops being a check and becomes a formality.

---

## Recommendation

**Three tiers, in this order. The first two are worth more than the third and
cost less.**

### 1. Text metrics, not pictures — for defect class #2 — **built**

`Tests/TextMetricsTests.swift`. Every localized caption is measured with the
font and the width the layout can actually give it, and the check fails when it
does not fit. No images, no baselines, six languages at once, and a seventh
covered the day it is added.

The budgets are derived rather than guessed: the tile width minus the padding,
minus the measured width of the glyph, the percentage and the countdown beside
it, minus a declared minimum bar width — 40 points, the one judgement in the
file and named as such. A caption may shrink by a fifth before it truncates, so
the budget is what fits after that shrink.

Measured headroom as it stands:

| | budget | tightest language |
|---|---:|---|
| Medium row caption | 139 pt | Russian, 27 % spare |
| Small tile header | 114 pt | Russian, 9 % spare |

Nine percent is thin, and it is the honest number: the small tile is 158 points
wide and Russian says `Использовано за неделю`. The check will fail rather than
truncate, which is the point.

Two negative controls keep the budgets meaningful — an over-long caption and a
three-line footer must both be rejected — and the whole set was verified
against a realistic regression: lengthening the German caption to
`In dieser Woche bereits verbraucht` fails two checks.

### 2. Accessibility-tree snapshots — for defect class #4 and much of #3

Snapshot what VoiceOver would say, as text, per size and per language:

```
GaugeRow  "Использовано за 5 часов, 31 %"
GaugeRow  "Использовано за неделю, 10 %"
GaugeRow  "Заполнение контекста, 44 %"
```

Text diffs are reviewable in a pull request, stable across OS versions, and
tiny. This is the highest-value snapshot testing available here, and it is not
image testing at all. The defect it would have caught — value announced before
label — took a real VoiceOver pass to find and cost an hour.

Defect #3, the inverted polarity, is better still: *the bar's fraction and the
number beside it describe the same quantity* is a plain unit test on
`GaugeMetric`, no rendering involved.

### 3. A handful of image baselines — for defect class #1 only

Where a picture is genuinely the only witness: the estimate chart's geometry.
Five outcomes, one size, one appearance, one language. **Five images, on the
primary macOS version only.**

That is the whole of it. Not 36, not 96. The chart is the one thing here whose
correctness lives in shape rather than in text, and a stub where a line should
be is invisible to every other kind of check.

### Where the boundary sits

A baseline earns its place when three things hold at once: the artifact is
stable, the change rate is low, and no cheaper check sees the same defect. The
chart passes all three. The caption grid fails the second and third. That is
the whole boundary, and it is why the recommendation is five images rather
than a matrix.

### What not to build

- Baselines per OS version. The regeneration workflow is worse than the bug it
  guards against, on a project with one maintainer.
- A tolerance threshold. Measured above: it cannot separate a clipped word
  from a clock tick.
- Baselines for anything whose text is already checked by tier 1 or tier 2.
  Two checks for one defect means two things to regenerate and one of them
  gets rubber-stamped.

---

## Order of work

0. Render the same fixture on both runners in CI and compare. One job,
   answers the feasibility question with a fact instead of this prediction.
1. Fixture and injected clock in the screenshot tool. Pays for itself in the
   README screenshots alone.
2. Tier 1, text metrics.
3. Tier 2, accessibility snapshots.
4. Tier 3, five chart images — and only if step 0 says the primary runner
   reproduces the local rendering.

Steps 1–3 are useful whatever step 0 returns.
