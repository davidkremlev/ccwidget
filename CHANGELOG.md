# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

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
