# Is the estimate measuring the right thing?

Prompted by a live reading: 118 hours of history, a perfectly measurable
0.07 %/h, and the verdict "not enough data" because R² was 0.64.

The hypothesis put to me was that R² gates linearity, that bursty work is not
linear, and that the threshold therefore hides the feature from a large part of
the audience rather than hiding unreliable estimates.

**The hypothesis is right about R². It is not the worst thing the measurement
found.** Replaying four days of real history through the current code says the
estimate was not mostly silent — it was mostly *wrong*.

---

## What actually happened over the four days

Replayed point by point: at each moment, the estimate is recomputed from the
history available up to that moment, exactly as the widget would have.

Both weekly windows in the data ended without exhausting the quota — peaks of
67 % and 14 %. **The correct answer, for the whole period, was "lasts until
reset".** Weighted by how long each verdict was on screen:

| What the widget showed | Share of the four days |
|---|---:|
| `Runs out ~<date>` — wrong both times | **58.8 %** |
| Silent | 25.5 % |
| `Lasts until reset` — correct | 15.7 % |

Nine changes of state across the period: the block appears, names a date,
falls silent, reappears.

Two figures that look contradictory and are both true. Only **10 of 181
samples** produced a date — but those samples were followed by long idle
stretches, and a verdict once computed stays on screen until the next history
line is written. A wrong answer computed rarely is displayed continuously.

---

## Why it named those dates

Not because of R². Because of a mismatch nobody had measured:

| At the ten moments a date was named | |
|---|---:|
| Usage at the time | 12–13 % |
| Formal observation base | 30 h |
| Of that, what the weighting actually reaches | **11 h** |
| Horizon the code therefore allowed | **298 h** |

The horizon rule is `span × 10`, and `span` is the full range of the points.
But the slope comes from a regression weighted with a 12-hour half-life, so
90 % of the weight sits in the last 11 hours. The guard was computed against
30 hours of evidence while the number it guards was computed from 11.

The result is a projection licensed to run 298 hours forward from 11 hours of
observation — a 27× extrapolation, where the design intended 10×, and 10× was
already generous. At 12 % used, on a week that reached 14 %, it announced
"runs out ~Thu 05:11" in red.

**This is a defect, not a design trade-off.** The two halves of section 7
disagree with each other, and nothing said so because no check compares them.

---

## What R² does here

Confirmed, and secondary:

```
R² over the period:  median 0.719,  25th 0.653,  75th 0.788
samples above the 0.7 threshold: 54.8 %
```

The distribution straddles the threshold. That is the flickering: the estimate
is not gated by a property of the data, it is gated by a coin landing near its
edge. And what it gates is the wrong property — for "will the total reach 100 %
before Thursday", the linearity of the path is not the question. A staircase
and a ramp with the same average rate arrive at the same place.

---

## What was tried instead, and what happened

### Average rate with a confidence interval on the exhaustion date

The suggested alternative, taken literally: rate from the data, spread across
sub-intervals, verdict from whether the reset falls inside the interval.

Measured on the same history — and it fails, for a reason worth stating,
because it is the same reason the original design reached for R²:

```
speaks:                         30.4 % of samples
true outcome inside interval:   85.5 %
average interval width:         329 percentage points
```

`0 % to 704 % by Thursday` is honest and useless. The uncertainty grows with
the distance projected, and six days out from a few hours of bursty work the
honest interval is unbounded. **Early in a week the answer is not hidden by a
bad statistic — it is genuinely not in the data.** An interval says so loudly;
R² says so by falling silent. Neither is more informative than the other.

### The same interval, used to choose between the three states

The version that works. Keep the three outcomes; let the interval decide, and
drop both R² and the horizon rule:

- interval entirely below 100 % → **lasts until reset**
- interval entirely above → **runs out ~date**
- interval straddles 100 % → **rate only**, no date

| | Current | Interval-driven |
|---|---:|---:|
| Silent | 25.5 % | **21.4 %** |
| Says something | 74.5 % | **78.6 %** |
| Correct "lasts until reset" | 15.7 % | 10.7 % |
| Rate without a date | 0 % | **67.9 %** |
| **Wrong dates** | **58.8 %** | **0** |

The block stops lying and starts saying "0.07 %/h" for most of the week, which
is a true and checkable statement, and names a date only when the arithmetic
supports one. Late in a window it tightens usefully on its own — at 66 % used
with six hours to the reset it gave `67 %, between 66 and 68`, and the week
finished at 67 %.

---

## Recommendation

**Three changes, in this order. The first is a bug fix and stands on its own.**

**1. Compute the horizon from the evidence that produced the slope.** Whatever
else is decided, `span × 10` must not be measured on a base the weighting does
not reach. Either the horizon uses the effective weighted span, or the
weighting is removed and the slope genuinely uses the whole base. Today they
contradict each other and that alone produced every false date in the data.

**2. Replace R² with the interval as the gate.** It measures what the question
needs — how much the rate varies, hence how far the projection can be trusted —
rather than how straight the path was. On the real history it removes every
false date and cuts silence from a quarter of the time to a fifth.

**3. Show the rate whenever there is one.** `rateOnly` already exists and is
never reached in practice; under the interval gate it becomes the normal state,
which is the honest description of most of a week. A widget that says
"0.07 %/h" all week and adds a date on Thursday is more useful than one that
alternates between a red date and nothing.

**What I am not recommending.** Predicting the level at the reset instead of
the exhaustion date is attractive — it is a bounded extrapolation, and the
horizon rule disappears — but it changes what the feature *says*, not just how
it decides, and the numbers above do not make that case on their own. Worth
considering separately if the three changes above leave the block feeling
thin.

**What this cannot settle.** One person's four days, two windows, both ending
comfortably under the limit. The false-date rate is measured; the true-date
rate is not, because nothing in this history ever ran out. A design that never
says "runs out" would score identically here and be useless. Before shipping a
change, the interval gate should be checked against a synthetic window that
does exhaust — and against a second person's history, if one becomes available.
