# Contributing

Thanks for looking. This is a small project with a written design document —
reading [SPEC.md](SPEC.md) before a non-trivial change will save you a round
trip, because most "why is it like this?" questions are answered there,
including the attempts that failed.

## Building

Requirements: macOS 14 or later, Xcode 16 or later. No package manager, no
dependencies — the project builds with what ships in Xcode.

```sh
git clone <repository>
cd ccgauge
./Scripts/reinstall.sh
```

The script builds Release, installs to `/Applications`, launches the app once
so the system registers the widget extension, and restarts `chronod`.

**That last step is not decoration.** The widget daemon keeps the previous
build of an extension loaded across a bundle replacement. Skip the restart and
your changes appear not to apply — the widget renders old code and the log
shows messages that no longer exist in your source.

## Running the checks

```sh
swiftc -swift-version 6 -strict-concurrency=complete -target arm64-apple-macos14.0 \
    Shared/*.swift App/Installer.swift App/SettingsEditor.swift \
    Tools/ccgauge-selftest/main.swift -o .build/ccgauge-selftest
./.build/ccgauge-selftest
```

`ccgauge-selftest` exercises the installer and the settings editor **inside a
temporary directory**. It must never touch a real `~/.claude`. If you add a
code path that reads or writes under the user's home, it takes the root as a
parameter — see SPEC section 5.2 for why that rule exists.

Two more tools, useful while working:

```sh
./.build/ccgauge-dump         # print the parsed snapshot and its diagnostics
./.build/ccgauge-screenshots  # re-shoot the README screenshots
```

Watching what the widget actually does:

```sh
log stream --predicate 'subsystem == "dev.illvminat.ccgauge"' --level info
```

## What a change should look like

- **Explain the why, not the what.** The diff already says what changed.
  Commit messages here are written in the imperative and spend their words on
  the reason, the constraint, or the failure that motivated the change.
- **Keep SPEC.md current.** It is the design document, not a historical
  artifact. If your change contradicts it, update it in the same commit.
- **No new dependencies** without discussing it first. Part of the point is
  that this thing builds from a clean clone with nothing installed.
- **Swift 6, complete concurrency, zero warnings.** The build is warning-free
  today; keep it that way.
- **User-facing strings go through the string catalogs** in `App/Resources`
  and `Widget/Resources`. Data — formatted numbers, paths, project names —
  goes through `Text(verbatim:)` so it is not looked up as a translation key.
- **Nothing user-identifying in the log as `.public`.** Paths, project names
  and raw field values are `.private`.

## Things that will be pushed back on

- Making the widget poll for data when Claude Code is closed. There is a
  contractual limit on this as well as a technical one — SPEC section 14
  spells out what is and is not acceptable. Read it before writing code.
- Adding network access of any kind. The project's claim that nothing leaves
  your machine is checkable by grepping for `URLSession`; keeping that true is
  worth more than any feature.
- Silent behaviour. Soft parsing that swallows a field, a fallback that hides
  which path was taken, an install that quietly rewrites something — all of it
  gets logged and surfaced. SPEC section 6.1 is the rule.

## What to expect from review

One maintainer, reviewing in evenings. Expect a first response within a week
and questions rather than silent rejection. Small focused changes get merged
faster than large ones, and a change that comes with a check in
`ccgauge-selftest` gets merged faster still.

If you are unsure whether something is wanted, open an issue before writing
the code. Nobody enjoys throwing away a weekend's work.

## Reporting a security problem

Do not open a public issue — see [SECURITY.md](SECURITY.md).
