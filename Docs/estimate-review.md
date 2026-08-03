# Is the estimate measuring the right thing?

Prompted by a live reading: 118 hours of history, a perfectly measurable
0.07 %/h, and the verdict "not enough data" because R² was 0.64.

The hypothesis put to me was that R² gates linearity, that bursty work is not
linear, and that the threshold therefore hides the feature from a large part of
the audience rather than hiding unreliable estimates.

**The hypothesis is right about R². It was not the thing doing the damage.**
Replaying four days of real history showed the estimate was not mostly silent —
it was mostly *wrong*, and for a reason that had nothing to do with R².

---

## 1. What the four days actually looked like

Replayed point by point: at each moment the estimate is recomputed from the
history available then, exactly as the widget would have. Both weekly windows
ended without exhausting the quota — peaks of 67 % and 14 % — so the correct
answer for the whole period was "lasts until reset".

| What the widget showed | Share of the four days |
|---|---:|
| `Runs out ~<date>` — wrong both times | **58.8 %** |
| Silent | 25.5 % |
| `Lasts until reset` — correct | 15.7 % |

Only 10 of 181 samples produced a date, but a verdict once computed stays on
screen until the next history line is written. A wrong answer computed rarely
is displayed continuously.

## 2. Why those dates appeared

| At the ten moments a date was named | |
|---|---:|
| Usage at the time | 12–13 % |
| Formal observation base | 30 h |
| Of that, what the weighting actually reached | **11 h** |
| Horizon the code therefore allowed | **298 h** |

The horizon rule is `span × 10` where `span` is the full range of points. The
slope comes from a regression weighted with a twelve-hour half-life, so ninety
per cent of the weight sits in the last eleven hours. **The guard was measured
on thirty hours of evidence while the number it guards was made from eleven.**

A projection licensed to run 298 hours forward from 11 hours of observation —
27×, where the design intended 10×.

---

## 3. The fix, and what it alone achieved

**Chosen: the horizon is computed from the effective weighted span.** The
alternative was dropping the weighting so the slope genuinely uses the whole
base.

Why this way round. Both rules have a recorded purpose and both purposes are
real — recency weighting exists so yesterday's marathon does not dominate
today's estimate, and the horizon exists so a short observation cannot license
a long projection. Dropping the weighting would discard a rule that works to
satisfy a rule that was mis-measured. Changing the guard to match the estimator
keeps both intentions and touches only the thing that was wrong.

The effective span is defined as the interval, measured back from the newest
point, carrying nine tenths of the weight. Nine tenths rather than all of it
because the exponential tail never ends. The number has a useful property: on a
base short against the half-life the weights are near-uniform and the effective
span is almost the whole span, so **the fix is invisible exactly where the two
measures always agreed**, and separates them only where they had diverged.

Re-running the same 118 hours after this fix and nothing else:

| | Before | After the horizon fix |
|---|---:|---:|
| **False dates** | **58.8 %** | **0** |
| Silent | 25.5 % | 25.8 % |
| Rate without a date | 0 % | **59.9 %** |
| Correct "lasts until reset" | 15.7 % | 14.3 % |

Average base 27 h, weighted reach 15 h — a horizon of 150 hours instead of 271.

`rateOnly` was a state the code could reach in principle and never did in
practice. It is now the normal state, which is the honest description of most
of a week.

---

## 4. Both schemes against windows that do exhaust

The objection to the first round stood: that history never ran out, so it could
only measure false alarms. A scheme that never warns would have scored
perfectly.

Eight synthetic weeks, four of which exhaust. The current scheme is the fixed
one; the interval scheme replaces R² and the horizon with a 95 % interval on
the rate, taken across six-hour blocks.

| Profile | Outcome | Date shown, current | Date shown, interval | Warning, current | Warning, interval |
|---|---|---:|---:|---:|---:|
| steady, survives | survives | 0 % | 0 % | — | — |
| steady, exhausts | at 134 h | 92 % | 93 % | 120 h | 126 h |
| accelerating, exhausts | at 135 h | 44 % | 31 % | **40 h** | 18 h |
| quiet then a surge | at 160 h | 16 % | 7 % | **18 h** | 3 h |
| weekdays only, survives | survives | 2 % | 2 % | — | — |
| decelerating, survives | survives | 0 % | 0 % | — | — |
| bursty, survives | survives | **0 %** | 2 % | — | — |
| bursty, exhausts | at 128 h | **89 %** | 43 % | 123 h | 122 h |

*"Warning" is how many hours before actual exhaustion the date first appeared.*

**The interval scheme is worse where it was supposed to be better.** On bursty
work that does exhaust — the audience the whole question was about — it shows a
date 43 % of the time against 89 %, because the spread across blocks keeps the
interval straddling 100 % and the warning flickers in and out. On the two
hardest profiles, accelerating and a late surge, it cuts the lead time from 40
hours to 18 and from 18 to 3. And it is not even better at false alarms: 2 % on
bursty-surviving where the current scheme has none.

Neither scheme handles a late surge well — 3 or 18 hours of notice on a week
that quietly filled up. That is a real limitation of extrapolating from the
past, and no gate fixes it.

---

## 5. Recommendation

**Do not replace R².** The case for replacing it rested on false dates, and
false dates came from the horizon, not from R². With the horizon fixed the
current scheme is at least as good as the interval scheme on every profile
measured and substantially better on two of them.

**What is left against R², honestly stated.** It still gates the wrong
property: the median over the real four days is 0.719 against a threshold of
0.7, so the block still flickers — eight state changes across the period. That
is worth fixing, but it is a stability problem, not a correctness one, and it
does not need the scheme replaced. Options, in increasing order of ambition:

1. Leave it. The flickering is between "rate only" and "lasts until reset";
   both are true statements and neither alarms anyone.
2. Add hysteresis: once a verdict is shown, require R² to fall further before
   withdrawing it. Cheap and removes the flicker without changing what is
   measured.
3. Revisit the gate later, with data from more than one person.

**Show the rate whenever there is one** is already true as a consequence of the
fix, not as a separate change: `rateOnly` went from never to 59.9 % of the
time.

**What these numbers still cannot settle.** The synthetic profiles are my
inventions, and a profile is a hypothesis about how people work. They were
chosen to include the shapes that ought to be hardest, but a second real
history would be worth more than all eight of them.
