# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.3] — 2026-08-17

### Added

- **Background updates.** A switch in the window's Details registers the app as a
  login item, so the tile keeps up with your usage whether or not a window is
  open. Off until you turn it on: a login item runs on every session without
  being asked, and that is somebody's trust to give rather than a default to
  take.

  What it took to get there is in `SPEC` 2.4. The obvious design — a small
  helper executable inside the app bundle, registered as a launch agent — does
  not work: WidgetKit refuses a process that is not the app, with
  `ChronoCoreErrorDomain` 27, and a reload from it changes nothing. Measured with
  a control, so background freshness had to be the app running in the background.

### Fixed

- **The last snapshot of a session was thrown away.** The watcher rations widget
  reloads to one a minute, and inside that minute it *dropped* a change instead
  of postponing it — on the reasoning that the exporter's next write would wake
  it again. True while you are working; false exactly when it matters, because
  the write that lands after your last prompt has no successor. So the tile kept
  the previous snapshot until WidgetKit came round on its own, up to half an
  hour, at the moment you stop working and look at the widget.

  Found by measuring the background agent rather than by reading the code: one
  write inside the window, then three and a half minutes of an unchanged tile
  with the app running. Postponed rather than dropped now, one reload owed per
  window however many writes arrive, and cancelled if the watcher stops.

- **The window says which build it is.** A row at the top of Details naming the
  version and, for a release, the commit that produced it. It said nothing about
  itself before, and that cost real time twice in one day: an installed bundle
  reported `0.3.2` while carrying work the `v0.3.2` tag does not contain, and
  answering "which build am I running" took `strings` on the binary and the
  modification date of the executable. A build made between two releases carries
  the same version number as the release before it, so the commit is the part
  that identifies it.

### Changed

- **The five-hour row says «сброшено» where it said «закрылось».** Russian only.
  On a screen, «окно» is a program's window, so «закрылось» was read as being
  about one — the owner closed an editor window, saw the row, and asked whether
  one had caused the other. It had not; the period had reset. The new word cannot
  mean an application window and matches the vocabulary the rest of the interface
  uses. German, Japanese and Chinese already said *ended* rather than *closed* and
  are untouched.

- **The reload log says what the tile drew.** `widget reload #22 (snapshot
  changed)` was the whole record, which could not answer whether a window had
  already expired in that snapshot. It now reads `moved 5h,context · five-hour
  expired · week open`. No values in it: percentages are raw fields, kept
  `.private`, and a `.private` value read back without a logging profile is
  redacted. The reason `budget window closed` is now `reload budget elapsed`,
  because it is about the reload ration and not about a limit window.

- **A reading that goes backwards is named.** Limits arrive with a model's reply
  and sit in the session until the next one, so a session writes the reading *it*
  last saw and a fresh timestamp promises nothing about the numbers. Measured on
  one machine's history: 522 rows, 13 steps backwards inside a single weekly
  window, the largest 27 % → 24 % six minutes apart. Nothing is discarded on that
  basis — the estimate gates on how well its line fits, so an old reading costs
  confidence rather than yielding a confident wrong answer — but it now logs
  `older reading: 7d` instead of passing in silence.

### Fixed

- **The window said the same thing twice.** Turning background updates on printed
  the new state under the switch, where it belongs, and again at the foot of
  Details. There is now an instrument for it rather than a promise to look
  harder: two identical sentences render as identical rows of pixels at the same
  offset, so a fingerprint per band finds them, and a check of its own fails if
  that instrument ever stops working.

## [0.3.2] — 2026-08-17

### Added

- **`brew install --cask davidkremlev/tap/ccwidget`.** One command instead of
  downloading a disk image and dragging.

  The uninstaller now ships inside the app bundle, and the cask runs it. That
  is the whole reason this is a release rather than a formula pointing at the
  last one: `brew uninstall` would otherwise delete the app and leave your
  `statusLine` running a file that no longer exists — a broken prompt on every
  redraw, caused by uninstalling. It takes `--yes` now, since nobody is there
  to answer, and says out loud that it went ahead without asking. Without the
  flag and with nobody at the terminal it does nothing, which is the other half
  of the same rule.

### Changed

- **The README screenshots are rendered from a fixture, not from a live
  account.** They used to be whatever the developer's afternoon looked like:
  a real session cost of $141.35 in a public README, real usage percentages,
  and the Estimate block reading *Not enough data yet* because the shots were
  taken just after a weekly reset — the one distinctive thing this widget does,
  photographed at its least convincing.

  `./Scripts/readme-screenshots.sh` writes a fixture and shoots against it in
  one command. The fixture is generated at shoot time rather than committed,
  because a row's countdown is a dynamic date drawn from the real clock: fixed
  timestamps render "2 yrs, 9 mths", which is the trap `RowCompositionTests`
  documents and which this walked into on the first attempt. The renderer now
  pins the time zone alongside the moment, so the pictures do not carry a city
  in them either.

### Fixed

- **Upgrading the app left the old exporter running, and nothing said so.**
  `~/.claude/ccwidget-export.py` is written by setup, not by installing the
  app, so a new version reached nobody who had already set it up — and the
  integrity check, which compares the file to its own recorded hash, called
  that "matches". It was true and beside the point.

  Worse, there was no way to fix it from the app: *Set up automatically* lives
  on the setup screen, which only appears while the app is unconfigured, and
  *Reinstall the exporter* lives inside the banner that appears only when the
  exporter has been **modified**. An old exporter raised nothing, so neither
  button could be reached.

  The exporter now carries the version that wrote it, and the window says "the
  exporter is from an older version" with the button that settles it.

### Added

- **Your status line keeps working.** Installing this used to blank it: the
  exporter prints nothing, so taking the `statusLine` key over left the prompt
  with nothing to show. Now whatever command was there is called by the
  exporter, handed the same input Claude Code sent, and its output printed
  unchanged — `ccstatusline`, a script, an inline `jq` pipeline, all of them
  keep rendering.

  Your data is written first and their command second, so a broken status line
  cannot also stop the widget getting data. Three seconds and a hanging command
  is abandoned. A missing, failing or slow command is recorded in the container
  and printed by `ccwidget-dump`, because the exporter cannot say it on stdout —
  everything it prints lands in your prompt.

  Setup now changes only `statusLine.command`, leaving `padding`,
  `refreshInterval` and the rest of the key as you had them; removal puts your
  command back rather than deleting the key. `SPEC` 13 had this filed under
  "version 2" and that was an error of priority — the cost was already being
  paid, and the uninstaller had already had to learn not to delete a wrapper
  that chains the exporter.


## [0.3.1] — 2026-08-17

### Fixed

- **The shipped app named the machine it was built on.** Two ways at once, and
  neither is visible to `strings`:

  `ENABLE_CODE_COVERAGE` defaults to YES, so the Release build carried LLVM's
  profiling machinery — `__llvm_prf_*` sections and 424 `__profc_` symbols,
  each one holding the absolute path of the source file it counts. The debug
  symbol table added 57 more, one per object file. Together they spelled out
  the account name and every folder above the project.

  Found by looking rather than by grepping: `strings` reports the paths only
  obliquely, and "I grepped it and it looked clean" would have been the wrong
  answer. The release script now builds with coverage off, strips debug
  symbols before signing, and **refuses to continue** if a byte search still
  finds the home path, a profiling symbol or a debug path entry in either
  binary.

- **The backup of your settings was briefly world-readable.** An atomic write
  lands at 644 and the chmod to 600 followed it, so between the two calls a
  copy of `settings.json` — which can hold environment variables and keys —
  was readable by every local account, and permanently so if the process died
  in between. It is opened 0600 now, and the mode is read back rather than
  assumed, because `open` masks it through the umask.

- **A test fixture carried eight characters of a real session id.** Not
  synthetic, whatever the audit's summary said: it was the start of a Claude
  Code session UUID that still exists on the machine this was built on. It
  identifies nothing to anyone else — that is why the exporter truncates to
  eight characters — but a fixture should be made up, and this one was not. The
  value is not quoted here for the same reason it was replaced.

  0.3.0 was never distributed — the repository is private and nobody had the
  file — but the tag stays where it is rather than being rewritten, and this
  is the build to use.

## [0.3.0] — 2026-08-17

**The first build that can be given to somebody else.** Everything before this
was ad-hoc signed, which meant macOS refused to open it on any machine that had
not compiled it — the single fact that kept the audience down to people who own
Xcode. This one is signed with a Developer ID, hardened, notarized by Apple and
stapled, and the release script checks the only thing that matters: it takes the
app back out of the disk image and asks whether Gatekeeper would open it and
whether it carries its own ticket, so it works offline too.

Numbered 0.3.0 rather than 0.2.0 because `v0.2.0-dev` already marks the 0.2
state and everything below arrived after it. A release that reused the number
would be claiming a state that already has a mark.


### Known gaps

- **On more than one Mac the estimate reads low.** The limits are per account
  and arrive correct everywhere; the history behind the estimate is per machine
  and sees only that machine's work, so the rate is measured from a fraction of
  the spending and the date lands later than the truth. Now stated in the README
  where the estimate is described. Not fixed, and the three obvious fixes are
  each worse than the warning — pooling histories would send data off the
  machine, suppressing the estimate on one machine needs a signal the data does
  not carry, and hiding it everywhere takes the feature from everybody.

- **Code comments and SPEC.md are in Russian.** Comments are being translated;
  the specification follows later.
- **Larger text has no effect anywhere in this app.** macOS offers no route to
  it: the accessibility *Text size* pane lists only applications that have
  opted in, and this one is not among them, while SwiftUI's semantic fonts on
  macOS do not scale with `dynamicTypeSize` the way they do on iOS. Rendered
  at `accessibility5` the three widget sizes come out byte for byte identical
  to the default — `./.build/ccwidget-screenshots out --type-size
  accessibility5` will show you. Someone who needs bigger text has nothing to
  turn on. Finding and adopting whatever macOS actually wants here is open
  work, not a decision that has been made.
- **The four non-Russian localizations have had no native review.** German,
  Spanish, Japanese and Simplified Chinese are one developer's best judgement.
  The row captions were rewritten once already after reading them aloud caught
  word-for-word translations that nobody says.

### Fixed

- **`Scripts/uninstall.sh` could delete a `statusLine` that was not ours.** It
  decided ownership by grepping the whole of `settings.json` for the substring
  `ccwidget-export.py`, so a status line of the user's own that chains the
  exporter — or a hook that merely names it — made the key ours and the key was
  deleted. The app-side removal has always compared `statusLine.command`
  exactly; the fallback, the one that runs when the app is already broken, was
  the weaker of the two. It now makes the same comparison, and the exporter
  file survives when anything else in the file still refers to it. An
  unparseable `settings.json` stops removal instead of proceeding blind.

  Found by a security review, not by use. What let it live was that nothing
  checked this script at all: it edits a file it does not own, and it had no
  check of any kind. `Scripts/check-uninstall.sh` now runs it against a
  stand-in `HOME` in fourteen cases — one per state the status line can be
  found in, plus a path spelled with a tilde, a settings file behind a symlink,
  and the file changing while the confirmation prompt waits. Against the old
  script sixteen of its fifty-seven assertions fail.

- **The Russian setup screen had a button cut off: "Показать инструкцию по
  ручн…".** The two buttons of the second step sit in one `HStack` inside a
  460-point window, and that pair needs 498 points of the 412 available. The
  title now names the sheet it opens — "Настройка вручную", the same words as
  that sheet's heading — and the pair comes to 348.

  Found by the check written for the step, not by looking: the setup screen is
  only reachable before setup, which is exactly when nobody is running the app
  from a working install. What made it findable was fixing the check first —
  the earlier version measured the strings `String(localized:)` returns inside
  the test bundle, and reported the same 77 points of headroom in all six
  languages. There is no catalog in that bundle, so those were six copies of
  the English. Widths now come from the catalog on disk, the way the window
  header's already did, and the assumption underneath is a check of its own.

  The widest translation left is Spanish at 395 points of 412. The numbers for
  all six are in the check, because seventeen points is not a margin anyone
  should have to rediscover.

- **The widget kept showing an age from a snapshot it no longer had.** The
  window read "updated now" while both widgets beside it read "2 minutes ago",
  off the same file. A message had gone out, the context had grown by a
  thousand tokens and stayed on 76 %, and the rule that decides whether the
  widget is worth reloading looked at three percentages — none of which had
  moved. So nothing asked the widget to look again, and the timeline it was
  holding went on counting the age from where it had started.

  The moment the snapshot was taken is part of that rule now. The reasoning
  that left it out — the age ticks by itself, drawn by a pre-generated timeline
  without the daemon — is true of the age growing and false of the age being
  reset, which is what a new snapshot does to it.

  What it costs, measured on 127 hours of real history: at most about 960
  reloads under the new rule against at least 30 under the old one. Both are
  bounds rather than counts — the history file carries only the weekly
  percentage, and the rule reads three — so the increase is real and its size
  is bracketed rather than pinned. The ceiling did not move: one reload a
  minute is what section 2.3 chose deliberately, and the new rule reaches it
  during active work where the old one rarely did.

  Which raises the stake on the one assumption in `SPEC` 2.3 that cannot be
  checked — that reloads asked for by the app cost less budget than the
  system's own. The assumption did not change and neither did the ceiling; how
  hard the widget leans on both did. Both places now say what it looks like if
  the assumption is wrong: the widget stops updating in the middle of the day
  and revives by itself later, with no error and no log line. That is a budget
  symptom, not a watcher defect, and the knob for it is
  `minimumReloadInterval`.

  What remains after the fix is a minute, and it is accepted rather than
  outstanding: while an agent is working the window says *updated now* and the
  widgets say *1 minute ago*, because the widget is holding a snapshot as old
  as the rationing allows. Consistency and freshness pull against each other
  here and the budget settles it — the window is deliberately not slowed to the
  widget's pace, since it is open because somebody opened it and redrawing it
  costs nothing. `SPEC` 2.4 has the reasoning; README tells the reader before
  they file it as a bug.

- **A row whose window had ended counted down to "0 min".** Seen in the
  morning: the five-hour row read *resets Tue 00:30 · 0 min* twelve hours after
  that reset had happened. The countdown floors at zero, so a reset in the past
  reads as one about to happen.

  A row now knows whether the window it describes has ended, and says so
  instead: a dash, an empty bar, and *closed* where the countdown was. Not
  another degree of staleness — freshness answers how long ago we looked, this
  answers whether what we looked at is still in force, and the two are
  independent. The rows also age at different rates, which is the reason it is
  per row: a weekly percentage twelve hours old is roughly right, a five-hour
  one describes a window that has closed twice over, and dimming the whole
  snapshot cannot tell those apart.

  Spoken as *closed* rather than *no data*, because data did arrive — it is
  about a period that is over. The word is one word by measurement: the slot it
  shares with the countdown is 66 points, and "window closed" needs 82 in
  Russian.

  Accepted with it: during active work the row blinks to *closed* for a second
  or two at each five-hour boundary, until the next snapshot brings the new
  window. That is honest — the window really did end. While idle it stays
  closed until work resumes, which is exactly when the old number would
  mislead.

- **Restarting Claude Code emptied the widget.** A session's first status-line
  redraw carries no `rate_limits` key at all and a context window whose usage
  is `null` — two such lines in twenty-nine of a real log. The exporter
  replaces the snapshot on every redraw, so the numbers a person was looking at
  were overwritten with nothing until the first prompt of the new session. Every
  restart, every time.

  A payload without limits does not say the limits are zero; it says this
  redraw knows nothing about them, which is not news. The write is skipped now.
  The snapshot stays, its age goes on growing, and the age is what tells the
  truth about how current it is.

  One of the checks was holding the defect in place — it required an empty
  input to produce a snapshot, and its own comment named the session-start
  shape while doing so. Rewritten rather than joined by a second one.

  The skip is a fallback and does not happen quietly. It leaves
  `export-skipped.json` beside the snapshot saying since when, why and in which
  session, and `ccwidget-dump` prints it before anything else — an old snapshot
  means something different when the exporter is running and declining to write.
  Written on the way into silence rather than on every redraw, so the moment it
  started survives; deleted by the first real write. Not for debugging session
  starts, where the skip lasts seconds, but for the case nobody has seen:
  `rate_limits` going missing mid-session and staying missing, where the
  symptom would otherwise be indistinguishable from Claude Code not running.
  In 29 status-line calls across three sessions it never did go missing after
  appearing — which is an observation and not a guarantee.

- **The window header was cut off at the widest badge.** "Usage Widget for
  Claude C…" beside *Нужна проверка*, seen at an hour's age. Tier 1 passed it:
  the check measured the badge against what was left after the title and
  allowed the badge to shrink, but permission to scale is not an instruction —
  the layout took the deficit out of the title. The header now says which one
  gives way, and the check asserts the sum instead of one term, which is true
  whichever piece the layout picks.

- **The status badge was cut off in four of its twenty-four translations.**
  It was the only single-line text in the window with no shrink allowance, and
  "Einrichtung nötig", "Нужна настройка", "Requiere revisión" and "Нужна
  проверка" all needed one — the app's name and the badge together came to more
  than the header's 300 points, which puts the header on two lines. Found by
  measuring, not by looking: tier 1 of the rendering plan had only ever read the
  widget's catalog, and the window's was measured by nobody. It is now, for the
  two places in the window where width is actually a constraint.

- **The window drew day-old numbers as though they were current.** Section 2.4
  replaces a snapshot over a day old with an invitation to launch Claude Code;
  the widget did that and the window went on drawing its bars. Which left the
  window with two states for old data, *outdated* and *abandoned*, that were
  identical in every respect — same badge, same colour, same bars — and so with
  no way to notice that one of them did nothing. The window is also where the
  comparison against the official Usage panel happens, which makes day-old
  percentages worse there than on a tile.

- **Removal did not say when it had rebuilt `settings.json`.** Installation has
  said so since the beginning: if the key cannot be cut out surgically the file
  is rewritten, key order and indentation go, and the person is told and
  pointed at the backup. Removal edits the same file with the same fallback and
  said nothing. The asymmetry was an oversight, not a decision; both paths now
  report it in the same words, and a check removes an escaped key through the
  real uninstall and reads the sentence back out of the window.

- **The window and the widget disagreed about how old the data was.** At one
  moment the window read "updated 42 seconds ago" and both widgets beside it
  read "1 minute ago", off the same file. Neither surface knows the time: the
  widget draws a timeline entry stamped up to a minute before the pixels
  appear, and the window reads its clock on a timer. Two quantised clocks on
  independent grids gave two answers.

  Both now measure from the start of the same minute, and the age is floored
  to whole minutes — a widget redraws once a minute, so "42 seconds ago" is a
  precision it does not have and the window beside it should not claim.
  Anything at or below zero reads as the present instead of "in 0 seconds",
  which is what a snapshot stamped after the entry on screen used to produce.

  The check is the one that would have caught it: at one instant, with one
  snapshot, each surface reaching its clock the way it really does, the two
  strings must match character for character — swept across the minute and
  across every wording boundary. It fails on the old code.

  Freshness moved onto the same clock, for the same reason. It says the same
  thing about the same snapshot without words — dimmed or not, numbers or an
  invitation — and two surfaces landing either side of a threshold dimmed at
  different moments. That check fails on the old code too: at 299 seconds, back
  when five minutes was still a threshold, the widget read *fresh* while the
  window read *recent*.

- **VoiceOver lost what sits beside the number.** Fixing the announcement order
  had replaced each row's label with a hand-built one, and the hand-built one
  carried only the caption and the percentage — so the countdown to the reset,
  the project name and the small tile's footer stopped being announced at all.
  A reader saw `49 % · 3 hr 59 min`; a listener heard "five-hour used, 49 %".
  Found by a second pass with the voice on, over all three widget sizes on a
  real desktop, and not by the text baseline — which had enshrined the loss,
  because it was written from the same wrong assumption.
- **The medium tile's footer was three fragments**, one of them beginning with
  the separator dot: "this session:", "$140.52", "· cache 100 %". It is one
  sentence now. The large tile's session rows were two apiece — "Cost", then
  "$140.52" — and are one each.

- **VoiceOver read the gauge rows backwards.** Each row carried its caption as
  the accessibility label and its percentage as the accessibility value, and
  VoiceOver announces a static element's value before its label — so the three
  rows came out as "30 %, five-hour used", "10 %, week used", "44 %, context
  used". Three bare numbers arriving before the things they measure is exactly
  the wrong order for someone who cannot glance back at the previous line. The
  caption and the value are now composed into one label, in reading order.
- **The Details disclosure announced itself as empty** — "Details, empty,
  button" — because the chevron beside the word contributed an unlabelled
  image, and it never said whether the section was open. It now reads
  "Details, collapsed" or "Details, expanded".
- **Detail rows were two unrelated items.** VoiceOver read "Exporter" and
  "matches the installed copy" separately, and the second means nothing on its
  own. They are one item now.

All three were found by running VoiceOver and listening, not by reading the
modifier lists, and confirmed the same way afterwards.

### Changed

- **The estimate stopped switching itself on and off.** Its R² gate had one
  threshold, 0.7, and on 118 hours of real history the statistic sat on it —
  median 0.710 — so the block appeared and disappeared eight times in five
  days, twice within a minute of itself. The gate now has two thresholds: 0.7
  to start showing a verdict and 0.58 to go on showing one.

  0.58 is measured, not chosen. Over that history R² dipped below 0.7 four
  times while a verdict was on screen; the two that were noise reached 0.648
  and 0.653 and came back, and the one that was real reached 0.507 after a
  sixty-seven-hour gap and did not. 0.58 is the middle of what those two
  bracket. Result on the same history: eight state changes become five, and
  the three that go are exactly the three that were flicker.

  The entry threshold did not move, and the reason is a measurement too — on
  a synthetic week that stays quiet and then surges, every step up the entry
  bar costs hours of the only warning it gets. Steadiness is not worth an hour
  of warning, so the asymmetry is made by letting the exit go. All four
  synthetic weeks that exhaust give the same lead time before this change and
  after it, to the sample, and those lead times are now floors in the suite.

  The gate keeps no state: it is replayed from the history file each time, so
  the verdict depends on the data and not on when the system happened to wake
  the widget.

- **The age caption no longer says "just now".** It said it for anything under
  five minutes, and on the fourth minute that stopped being true. The caption
  is the age and nothing else — "now" under a minute, then minutes, hours,
  days. How fresh the data is arrives as colour: normal, dimmed past an hour,
  replaced by an invitation past a day. `SPEC` 2.4 carries the decision.

  **Freshness lost a level as a consequence, not as a decision of its own.**
  *fresh* was under five minutes and *recent* was five to sixty, and the two
  drew identically — not dimmed, numbers shown. The difference earned its keep
  while the caption said "just now" under five minutes; once that wording went,
  nothing could tell the two apart on screen, and the watcher was still
  reloading the widget's timeline when the clock crossed between them, to get
  back a timeline that looked the same. Three levels now, one per appearance:
  normal, dimmed, replaced. Five minutes is not a boundary any more — not moved,
  removed; the nearest one is still the hour, where it always was.

  The rule that replaced the level is checkable, which the level never was: no
  two freshness levels may draw the same. A fourth one fails the suite until it
  is visible, and a reload for a change nobody can see fails it too.

- **Every enum in the project now has to make an observable difference**, in
  whatever it is responsible for — the widget's appearance for freshness, the
  verdict on screen for the estimate, the message and the suggested action for
  an installer failure, the diagnosis for the estimate's gate. One guard per
  enum, each verified by planting a collision and watching it fail.

  Two of them were only writable after the thing they guard came out of a view.
  The estimate block composed its caption, its colour and whether to draw the
  chart inside a `@ViewBuilder`, so nothing could tell *not enough data* from
  *usage is flat*, or *lasts until reset* from *runs out*: on everything a
  check could reach, each pair was equal. That is the shape the `.runsOut`
  defect lived in — announced in red for quotas that comfortably outlived their
  window, past eighteen checks that all tested the arithmetic. The window's
  badge and explanation came out of `StatusView` for the same reason, and that
  is how the missing *abandoned* branch above became visible at all.

- **The display name is now "Usage Widget for Claude Code".** It used to be
  "Gauge for Claude Code", which no longer connected to anything: people
  install `ccwidget` and something called *Gauge* appears in their
  applications. The bundle in Finder stays `CCWidget.app`; only the name
  shown to people changed.

- **Renamed from ccgauge to ccwidget.** The old name was already taken by a
  live project in the same niche — a Claude Code usage dashboard published on
  npm — and a Homebrew formula under that name would have collided with it in
  search and in people's heads. Bundle identifiers, the exchange directory,
  the Swift type prefix and the project file all moved with it. Anyone who
  installed an earlier build should remove `/Applications/CCGauge.app` by
  hand: a bundle under the old name keeps its own widget registration and
  reports the new exporter as a stranger's.

- **The forecast is now an estimate, and says so.** It could state a date
  from thirty minutes of history, extrapolating three hundred times further
  than its own base. Thresholds are ten points, a two-hour base, weighted R²
  of at least 0.7, and a horizon no further than ten base lengths — which
  binds "lasts until reset" too, since that is a claim about the future in
  exactly the same way a date is.

  Because that leaves seventeen hours of silence after a weekly reset, there
  is a third state: **rate without a date.** Speed is a measurement and is
  honest at any base length; the date waits for the horizon. The block is
  labelled *Estimate*, the date carries a tilde, and the length of the base is
  printed underneath.

- **The whole interface is localized.** Twenty-five strings in the app were
  still hardcoded English while their neighbours came from the catalogs, so a
  single screen could mix two languages.

### Added

- **What the setup screen says is now a baseline, not four `Text`s in a view.**
  `OnboardingStep` was the last enum in the project whose consequence no check
  could reach: the four steps differed only in literals inside
  `OnboardingView`, so nothing could tell whether a step said anything at all,
  let alone something different from its neighbour. The wording moved into
  `OnboardingStep.script`, which returns the headline, the paragraph and the
  button titles for a step and the two facts about the world it needs — whether
  Claude Code is installed, whether the widget's container exists.

  Six screens come out of four steps, and `Baselines/onboarding.txt` records
  all six. A second check requires the six to differ from each other; a third
  measures the button rows. That third one found the truncated Russian button
  above.

- **An application icon**, built in Icon Composer from two layers over a dark
  background: the grey ring track and the green arc at seventy per cent. The
  sources are in `Docs/icon/`. It compiles into `Assets.car` and a standalone
  `CCWidget.icns`, and CI now fails if either goes missing from the bundle —
  they arrive from `actool` rather than from a file we copy, so nothing else
  would notice their absence.

  It belongs to the application alone. The widget extension was given one as an
  experiment and it changed nothing anywhere: with no icon of its own the
  extension is already handed the app's by the system.

  **If you build from source and the old placeholder stays**, it is macOS's
  icon cache and not the bundle. Finder, the Dock and the widget gallery all
  showed a grey square while `NSWorkspace.icon(forFile:)` — the API they are
  built on — returned the real icon for the same path. Reinstalling,
  re-registering with `lsregister` and restarting `chronod` change nothing;
  clearing the cache does. README has the commands.

  **The widget gallery lists the app as "CCWidget"**, not by its display name,
  and that is settled rather than outstanding. The gallery takes the label from
  the bundle's name on disk — not from `CFBundleName`, not from
  `CFBundleDisplayName`, not from either of the extension's. Established by
  changing each in turn and looking; the evidence, including what eleven
  neighbouring bundles have in those fields, is in `SPEC` under *Именование*.

- **`ccwidget-replay`, a console tool that replays a `history.jsonl` through
  the estimate** and reports what the widget would have shown, for how long,
  and at every change of state. The figures published about the estimate came
  from scripts that were never committed, which made a published table
  impossible to re-derive; they are re-derivable now. The file it reads holds
  timestamps, percentages and reset times and nothing else, so a history from
  somebody else can be replayed without carrying anything about them.

- **Eight synthetic weeks in the checks, four of which run out of quota.** The
  one real history there is never exhausted, so it can measure false alarms and
  nothing else — a scheme that never warns would score perfectly on it. What
  these measure is how long before exhaustion the date first appears, recorded
  as floors that a later change may raise and not lower.

- **Removal.** A button in the app and `Scripts/uninstall.sh` as the fallback
  for when the app will not open. The `statusLine` key is deleted surgically
  rather than restored from a backup — other keys may have changed since
  installing, and rolling the file back would take those edits away. History
  is kept unless you ask for it to go.

- **Integrity checking.** The app records a hash of the exporter it installs
  and compares it on launch. It puts an executable file in the status line's
  path and used to never look at it again; the hash does not prevent
  tampering, it makes tampering visible.

### Fixed

- History truncation moved into the exporter. It lived in the app window,
  which a user may never open, so the two-thousand-line limit was never
  actually enforced.
- `SnapshotWatcher` is stopped when the window closes instead of leaking two
  file descriptors.
- Settings backups are written `0600` and pruned to the five most recent.
- No more `35% left` printed under `Week used 65%` — two polarities in one
  column was exactly what the design document forbids.
- The small size scales with Dynamic Type instead of a hardcoded 34pt, and
  VoiceOver reads percentages as percentages.

## [0.2.0-dev] — 2026-07-29

First-run experience and localization.

### Added

- First-run onboarding: detect Claude Code, install the exporter, wait for the
  first snapshot. Setup refuses to run before the widget exists on the desktop,
  because the exchange directory is created by the system when the extension
  first launches.
- Manual setup instructions for people who would rather not let an app edit
  their config.
- Localization into six languages — English as the source, plus German,
  Spanish, Japanese, Russian and Simplified Chinese. Russian plural forms are
  filled in rather than ignored.

### Changed

- An existing `statusLine` is shown before it is replaced, and
  `settings.json` is copied aside first.
- Formatted numbers, paths and project names render through `Text(verbatim:)`
  so they are not looked up as translation keys.

## [0.1.0-dev] — 2026-07-29

Data path, widget, forecast.

### Added

- Status line exporter installed as a template, with the exchange path
  substituted at setup time.
- Widget extension with all three families — small, medium and large.
- Weekly quota forecast: weighted least squares over the current window, with
  a chart in the large size. It declines to guess below five data points, a
  thirty-minute spread, or flat usage.
- Snapshot watcher that reloads the widget timelines when the numbers actually
  change, throttled to at most once a minute.
- Diagnostics: every soft-parse failure goes to the unified log and to a
  `diagnostics` list on the snapshot, rather than vanishing.

### Fixed

- Percentages arrive both integral and fractional (`28.000000000000004` was
  observed live). The exporter rounds on write and the model tolerates either;
  before this, one fractional value silently dropped an entire limit window.

### Security

- The exporter and history truncation refuse to write through symlinks
  (`O_NOFOLLOW`, `O_EXCL`, `lstat` check). It runs dozens of times a minute
  with the user's privileges, so a planted symlink turned it into a primitive
  for destroying arbitrary files.
- A symlinked `settings.json` is written through, not replaced. Dotfile
  managers are common in this audience, and a silently broken link left the
  real config without a status line.
- The exchange path is substituted as a proper Python literal, so a path
  containing a quote or newline cannot escape into executable code.
- The interpreter is pinned to an absolute path chosen at install time,
  preferring root-owned `/usr/bin/python3` over user-writable Homebrew paths.
- Standard input is capped at one mebibyte.
- `project.path` is no longer written at all and `sessionId` is truncated to
  eight characters. Neither is displayed anywhere, and a project path can name
  a client.
- User paths, directory listings and raw field values log as `.private`.
- `~/.claude` is created with mode `0700` when this project is the one
  creating it.

[Unreleased]: ../../compare/v0.3.3...HEAD
[0.3.3]: ../../compare/v0.3.2...v0.3.3
[0.3.2]: ../../compare/v0.3.1...v0.3.2
[0.3.1]: ../../compare/v0.3.0...v0.3.1
[0.3.0]: ../../compare/v0.2.0-dev...v0.3.0
[0.2.0-dev]: ../../compare/v0.1.0-dev...v0.2.0-dev
[0.1.0-dev]: ../../releases/tag/v0.1.0-dev
