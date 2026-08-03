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
   measured. — *Taken. Section 6.*
3. Revisit the gate later, with data from more than one person. — *Open, and
   section 6.6 sharpens what it would settle. `SPEC` 14 carries it.*

**Show the rate whenever there is one** is already true as a consequence of the
fix, not as a separate change: `rateOnly` went from never to 59.9 % of the
time.

**What these numbers still cannot settle.** The synthetic profiles are my
inventions, and a profile is a hypothesis about how people work. They were
chosen to include the shapes that ought to be hardest, but a second real
history would be worth more than all eight of them.

---

## 6. The flicker, measured and removed

Option 2 from the list above, taken up on the owner's decision, with the
condition attached: measure the warning time on the weeks that exhaust, before
and after, and drop the whole thing if any of them shortens.

Everything below is reproducible. `./.build/ccwidget-replay <history.jsonl>`
replays a real history; `Tests/EstimateProfilesTests.swift` builds and replays
the eight synthetic weeks. The scripts behind section 4 were not committed and
the tables there could not be re-derived — that is fixed here.

The history replayed below is the one from section 1, at 183 lines and 119.3
hours as of 3 August 2026. It is a live file and it goes on growing, so a
replay run later will not match these tables to the decimal. The shape of the
answer does not depend on that; the exact percentages do.

### 6.1 What the eight changes actually were

Replaying the 118 hours line by line, under the single 0.7 threshold:

| When | Change | R² |
|---|---|---:|
| 29 Jul 13:58 | silent → lasts until reset | 0.730 |
| 30 Jul 06:00 | lasts until reset → silent | **0.648** |
| 30 Jul 06:00 | silent → lasts until reset | 0.719 |
| 30 Jul 07:00 | weekly reset | — |
| 31 Jul 08:23 | silent → lasts until reset | 0.710 |
| 31 Jul 08:24 | lasts until reset → silent | **0.699** |
| 31 Jul 10:01 | silent → rate only | 0.707 |
| 3 Aug 09:15 | rate only → silent | 0.507 |

Two of them are 36 seconds apart and two are one minute apart. The block was
not responding to anything about the week; R² was sitting on the threshold —
median 0.710 over 65 fits — and crossing it in both directions.

(Section 5 quotes 0.719 for the same statistic. It was measured on the same
file two days earlier and a hundred lines shorter. Every figure in this section
is from the 183-line snapshot named above; the drift between the two is what a
live file does, not a disagreement.)

### 6.2 Where the second threshold goes

Four times R² fell below 0.7 while a verdict was on screen. What separates them
is not depth alone but what happened next:

| Dip reached | Recovered after | What it was |
|---:|---|---|
| 0.648 | 36 seconds | the statistic wobbling |
| 0.653 | 1.6 hours | the statistic wobbling |
| 0.537 | 6.7 hours | (the gate was shut at the time) |
| 0.507 | never, within the record | a 67-hour gap in the history; the line genuinely described nothing |

So the exit threshold has to sit **below 0.653** — or the wobble still switches
the block off — and **above 0.507** — or a fit that has actually stopped
working keeps its verdict. **0.58 is the middle of that interval**, which is as
far from both mistakes as one history can put it.

Two things worth saying about that number. It is not a round one on purpose:
the interval it centres came from measurement and rounding it to 0.6 or 0.55
would move it towards one of the two errors for no reason. And its margin,
0.073 either way, is about **0.8 of the standard error of R²** at this
operating point — 0.089, from `2R(1−R²)/√n` with a median effective sample size
of 32 behind those fits. One history does not support finer than that, and more
digits would be invention. The effective sample size is the weights' own,
`(Σw)²/Σw²`, not the number of lines: with a twelve-hour half-life the two
differ by a factor of four.

Sweeping the exit threshold over the same history confirms the interval rather
than assuming it:

| Exit threshold | State changes |
|---:|---:|
| 0.70 – 0.66 | 8 |
| 0.64 – 0.52 | **5** |
| 0.50 – 0.40 | 6 |

A plateau, not a knife edge, and it ends exactly where the two dips said it
would.

### 6.3 The entry threshold does not move

The instruction was to enter conservatively and leave with a delay. Measured,
the first half of that costs warning time and buys nothing.

Sweeping the entry threshold across the four weeks that exhaust:

| Entry | steady | accelerating | quiet then a surge | bursty |
|---:|---:|---:|---:|---:|
| 0.70 | 118.8 h | 48.3 h | **4.7 h** | 114.2 h |
| 0.76 | 118.8 h | 48.3 h | **4.7 h** | 114.2 h |
| 0.78 | 118.8 h | 48.3 h | **4.5 h** | 114.2 h |
| 0.80 | 118.8 h | 48.3 h | **3.8 h** | 114.2 h |
| 0.86 | 118.8 h | 48.3 h | **0.3 h** | 114.2 h |

Three of the four are insensitive because a week heavy enough to exhaust
produces a high R² — the signal is large against the one-percent quantisation.
The fourth is the one that matters: a week that stays quiet and then surges runs
right along the gate, and every step up the entry threshold takes hours off the
only warning it gets. There is apparent headroom to 0.76, and it is apparent
only: it is the distance to a cliff that one invented profile happens to sit at.
Fitting a constant to that would be fitting it to noise.

So the asymmetry is made by letting the exit go, not by pulling the entry in.
That is also the only direction that **cannot** cost warning time, which is what
the condition on this work demanded.

### 6.4 What it bought

Same 118 hours, entry 0.70, exit 0.58:

| | Before | After |
|---|---:|---:|
| **State changes** | **8** | **5** |
| False dates | 0 | 0 |
| Silent | 26.0 % | 24.7 % |
| Rate without a date | 59.7 % | 60.9 % |
| Correct "lasts until reset" | 14.3 % | 14.4 % |

The three that went are exactly the three that were flicker. Each of the five
that remain answers to something that happened: the first verdict of a window,
the weekly reset, the first verdict of the next window, a move from "lasts until
reset" to "rate only" as the weighted reach shrank, and the withdrawal at
R² = 0.507 after the 67-hour gap. **There is no flicker left in this history**,
which is a stronger statement than "three fewer".

### 6.5 The condition: warning time before and after

The four weeks that exhaust, replayed with the exit threshold set equal to the
entry threshold — the rule exactly as it was — and then as it ships:

| Profile | Runs out at | Warning before | Warning after | Date shown before → after |
|---|---:|---:|---:|---|
| steady, exhausts | 134 h | 118.83 h | **118.83 h** | 92.3 % → 92.7 % |
| accelerating, exhausts | 135 h | 48.33 h | **48.33 h** | 38.4 % → 38.4 % |
| quiet then a surge | 160 h | 4.67 h | **4.67 h** | 3.1 % → 3.1 % |
| bursty, exhausts | 127 h | 114.15 h | **114.15 h** | 89.9 % → 89.9 % |

Identical, to the sample. Not luck: the entry threshold did not move, so the
moment a date first appears cannot move. That is now a check rather than an
argument — `hysteresisOnlyEverAdds` asserts that whenever R² is at or above the
entry threshold the gate admits a verdict, over every fit of all eight weeks.

Two checks, and they cover different halves. That one covers the latch: nothing
about the exit threshold, and no bug in the replay, can make the gate refuse
what a single threshold at the same bar would have allowed. It says nothing
about where the bar is, because it is written against the constant. The lead
times themselves are recorded as floors and the false-date shares as ceilings,
and those cover the bar: setting the entry threshold to 0.80 takes the surge
week from 4.67 hours of warning to 3.83 and `leadTimeIsNotLost` fails on it —
checked by doing it, not by expecting it to.

What neither covers is an exit threshold set absurdly low. On the real history
that shows up immediately — below 0.52 the state changes go back up, because a
fit that has genuinely died keeps its verdict — but the synthetic weeks never
put R² that low, so the suite would not notice. The replay tool is the check
for that one, and it needs a history.

**The cost side, stated.** Hysteresis holds a date slightly longer when the date
was wrong too: on the decelerating week that survives, a date is shown 10.17 %
of the time against 10.06 %, and on the steady week that exhausts 92.7 % against
92.3 %. Tenths of a per cent, in the direction that costs something.

### 6.6 What had to change about the profiles, and why it matters

The eight weeks were rebuilt for this — the originals were never committed — and
rebuilding them turned up something the first round hid. A profile generated
from a smooth curve fits a straight line to three decimal places: pooled R²
across all eight came out at a median of 0.93, against 0.71 for the real
history. **A gate on R² is untestable on data whose R² is never near the gate.**
Adding what real work has — sessions in unequal lumps, pauses inside them, whole
nights with no lines at all — brings the profiles down to where the gate lives,
and `theGateIsReached` now checks that all three gate states occur, so a future
profile set that drifts back to being too clean says so instead of passing
everything.

The gap that remains is honest and worth writing down: even with the lumps, the
weeks that exhaust sit well above the gate, because a week heavy enough to run
out of quota moves the percentage fast enough for a line to describe it. The
real history sits near the gate because it is a *light* week — 0.14 %/h against
0.94 for the lightest exhausting profile. So the R² gate mostly binds on people
who are in no danger, and mostly does not bind on the people the estimate is
for. That is a finding about the gate, not about hysteresis, and it is the
strongest argument in this document for revisiting R² later with more than one
person's data.
