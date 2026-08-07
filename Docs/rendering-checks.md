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

Nine percent is thin, and it is the honest number: the small tile is 164 points
wide — measured, section 9 — and Russian says `Использовано за неделю`. The check will fail rather than
truncate, which is the point.

Two negative controls keep the budgets meaningful — an over-long caption and a
three-line footer must both be rejected — and the whole set was verified
against a realistic regression: lengthening the German caption to
`In dieser Woche bereits verbraucht` fails two checks.

### 2. Accessibility snapshots — for defect class #4 and much of #3 — **built**

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

`Tests/AnnouncementTests.swift`, with the baseline in
`Tests/Baselines/announcements.txt`: five states, twelve announcements, one
file a reviewer reads. The locale is pinned to `en_US_POSIX`, because a
baseline that differs between two correct machines is a baseline nobody
trusts.

**One correction to the plan.** It cannot read the platform accessibility
tree. SwiftUI builds that lazily, only when an assistive client attaches: an
`NSHostingView` in a test process reports `AXGroup` and no children at all —
measured, not assumed. So the baseline holds the strings the views compose,
and the bridge from a composed label to what VoiceOver actually says stays a
manual check. That bridge was verified by listening, and the wording and order
— which is where the defect was — are now held automatically.

Making that possible changed production code: the announcement is a `String`
rather than a `Text`, because a `Text` cannot be read back. That is most of
why the order was wrong for as long as it was.

Verified against a regression rather than assumed: swapping the composition
back to value-first fails both the baseline and the property check beside it.

The same tier closed the two view-state enums. `WindowState` and
`OnboardingStep` moved out of their views into `App/WindowState.swift` — the
first is a decision about what the state of the world means, taken from four
values the model already publishes, and the second was four assignments
scattered through a four-hundred-line view. Neither is view code, and while
they were private to views, five and three of their cases respectively were
unreachable by any check.

Defect #3, the inverted polarity, is better still: *the bar's fraction and the
number beside it describe the same quantity* is a plain unit test on
`GaugeMetric`, no rendering involved.

### 3. A handful of image baselines — for defect class #1 only — **built**

Where a picture is genuinely the only witness: the estimate chart's geometry.
Five outcomes, one size, one appearance, one language. **Five images, on the
primary macOS version only.**

That is the whole of it. Not 36, not 96. The chart is the one thing here whose
correctness lives in shape rather than in text, and a stub where a line should
be is invisible to every other kind of check.

`Tests/ChartBaselineTests.swift`, baselines in `Tests/Baselines/chart-*.png`.
Three things had to be true before a single byte could be compared, and none of
them was:

- **The tool had to become deterministic.** `--fixture` and `--now` were added
  to the screenshot tool, with a snapshot and a history committed under
  `Tests/Fixtures/`. Two runs three seconds apart are now byte-for-byte
  identical across all six images; before, four of the six differed.
- **The suite had to be serialized.** Rendering the same view twice gave
  different bytes while the suites ran in parallel, though the same renderer in
  a plain executable is stable across processes. Whatever the shared state is,
  a baseline suite cannot race against one.
- **Two formatters had to take a locale.** `ForecastBlock` renders against the
  environment's locale and formatted against the process locale, so a baseline
  taken here said "0,4 %/h" and "Ср 08:01" where an American machine would say
  "0.4" and "Wed 8:01 AM". A view that disagrees with itself about locale is a
  defect in its own right; the baseline only made it visible.

And the first run found something the analysis had not predicted: rendering
`ForecastChart` directly bypasses `ForecastBlock`, which is where the decision
*not* to draw the chart lives. The initial "not enough data" baseline was
therefore a picture of the very stub this tier exists to prevent — of a view
the product never displays. Rendering the block instead is the fix, and it is
the reason the tier is worth having: a text check would have agreed with itself
all the way.

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

## Where tier 1 went blind, and what took over

Tier 1 measures strings. The countdown to a reset stopped being one: it is now
`Text(date, style: .relative)`, formatted by the system while the extension is
asleep, and the code never sees the characters. That line — "resets Fri 11:50 ·
3 hr 38 min" — is the widest thing on a medium row and the one that overflowed
in German twice. **The cheap trap no longer covers it.** Saying so plainly
matters more than the replacement: a check that quietly stops covering
something is worse than one that was never written.

What covers it now is `Tests/DynamicDateWidthTests.swift`, in the render tier.
It renders the real `DetailLine` through `ImageRenderer` at scale 1 and takes
the width of the resulting image, which is the width of the laid-out text. Six
languages, six intervals from forty-five seconds to nearly a week, both the
counting and the closed form, measured against the same tile geometry tier 1
uses.

Three ways this is weaker than what it replaced, all of them worth knowing
before trusting it:

- **It costs a render per case.** Seventy-eight renders where tier 1 did string
  arithmetic. Still seconds, not minutes, but it is no longer free.
- **It cannot pin the wording.** The dynamic styles read the system clock and
  ignore the date the surrounding view was stamped with — measured, section 2.3
  of `SPEC.md`. An interval of "22 h 59 min" prints as two units just before the
  hour and one just after, so the check asserts fitting, never equality.
- **It measures the line, not the row.** Tier 1 derived what was left after the
  glyph, caption and percentage had taken their share. Here the budget is a
  fraction of the tile, which is a judgement rather than a derivation.

A guard against the failure mode that would make all of it meaningless — a
render producing nothing and every width coming out as zero — sits in the same
file and asserts the instrument returns pixels.

---

## The render tool renders one language, and the tile ships in six

**A regression the whole ladder missed, 7 August 2026.** The medium tile shipped
with no bars on its two limit rows. Two hundred and fifteen checks were green,
the render tool's pictures looked right, and the tile on the desktop had a
caption, a percentage and a countdown where a bar used to be.

Three separate reasons it got through, and all three are worth keeping:

**The tool was run in English.** `DetailLine` had been placed in the row's
`HStack` beside the bar, with `layoutPriority(2)`. The bar is the only flexible
element there, so the longer the line, the narrower the bar — and "сброс Чт
07:00 · 5 дн 20 ч" is half again as wide as its English original. Re-running
the same tool with `-AppleLocale ru_RU -AppleLanguages "(ru)"` reproduced the
defect immediately. **The tool was not lying; it was asked the wrong question.**
Anything that can overflow gets rendered in Russian and German too, not only in
the language of the README screenshots.

**No tier looks at what a row is made of.** Tier 1 weighs strings, tier 2 what
is spoken, tier 3 compares chart pictures. A row that loses its bar keeps every
string it had, so nothing moved. `Tests/RowCompositionTests.swift` closes that:
it renders the row and measures the bar, in six languages, and fails on the
layout that shipped.

**Measuring the right thing took three attempts, and the first two passed for
the wrong reason.** Counting the bar's tint measured the fill, which at 25 %
usage is a quarter of the bar; rendering at 100 % to fix that turned the level
`depleted`, whose tint is grey, and the colour filter found nothing at all. What
holds is geometry — the bar is the longest horizontal run of ink in the row —
because it does not depend on the level, the percentage or the palette.

---

## Manual pass before a release

What no tier can reach, listed so that it is done deliberately rather than
remembered. Everything here has the same shape: the check exists, it passes,
and it still cannot see the last step between what the code composes and what
the person gets.

**The estimate chart speaks.** Put the large widget on the desktop, turn
VoiceOver on (⌘F5), and move to the chart. Expected: it says the chart's name,
the week's reading and — when a rate is measured — the rate, e.g. *"Week usage
chart, 62 %, 0.7 %/h"*. Then it moves on to the verdict beneath it.

Two ways this fails, and only one of them any check can see. If the wording is
wrong, `AnnouncementTests` catches it. **If the label is not attached to the
view at all, nothing catches it** — the chart simply falls silent and VoiceOver
skips to the next element, which is exactly how the chart behaved for months
while it was `accessibilityHidden(true)`. The tree is built lazily and only for
an attached assistive client, so a test process sees `AXGroup` with no children
(measured, section 2 above). Listening is the only instrument.

Worth doing in one non-English locale as well: the name comes from the catalog
and the numbers from the environment's locale, and those are two different
sources that can disagree.

0. Render the same fixture on both runners in CI and compare. One job,
   answers the feasibility question with a fact instead of this prediction.
1. Fixture and injected clock in the screenshot tool. Pays for itself in the
   README screenshots alone.
2. Tier 1, text metrics.
3. Tier 2, accessibility snapshots.
4. Tier 3, five chart images — and only if step 0 says the primary runner
   reproduces the local rendering.

Steps 1–3 are useful whatever step 0 returns.
