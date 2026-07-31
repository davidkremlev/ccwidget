# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Known gaps

- **Screenshots were taken right after a weekly reset**, so the Estimate block
  reads *Not enough data yet* — the fit quality is below threshold that soon
  after the counter drops. The behaviour is correct and the wording is honest,
  but it shows the project's one distinctive feature at its least convincing.
  Re-shoot once a couple of days of history have accumulated and the estimate
  reports a rate with a date:
  `./.build/ccwidget-screenshots Docs/screenshots -AppleLocale en_US -AppleLanguages "(en)"`
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

[Unreleased]: ../../compare/v0.2.0-dev...HEAD
[0.2.0-dev]: ../../compare/v0.1.0-dev...v0.2.0-dev
[0.1.0-dev]: ../../releases/tag/v0.1.0-dev
