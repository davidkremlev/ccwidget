# Contributing

Thanks for looking. This is a small project with a written design document —
reading [SPEC.md](SPEC.md) before a non-trivial change will save you a round
trip, because most "why is it like this?" questions are answered there,
including the attempts that failed.

## Building

Requirements: macOS 14 or later, Xcode 16 or later (**with anything older than
Xcode 26 the app builds without an icon** — the `.icon` file needs it, and
Xcode 26 needs macOS 15.6; the CI job for the minimum OS says so out loud), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The app itself has no
dependencies — nothing is linked that does not ship with Xcode — but the
`.xcodeproj` is generated rather than committed, and XcodeGen is what
generates it.

```sh
brew install xcodegen
git clone <repository>
cd ccwidget
./Scripts/reinstall.sh
```

The script generates the project, builds Release, installs to `/Applications`,
launches the app once so the system registers the widget extension, and
restarts `chronod`.

**That last step is not decoration.** The widget daemon keeps the previous
build of an extension loaded across a bundle replacement. Skip the restart and
your changes appear not to apply — the widget renders old code and the log
shows messages that no longer exist in your source.

To open the project in Xcode, generate it first:

```sh
xcodegen generate && open CCWidget.xcodeproj
```

**Editing outside Xcode?** Point sourcekit-lsp at the project once, or every
diagnostic you see will be wrong:

```sh
brew install xcode-build-server
xcode-build-server config -project CCWidget.xcodeproj -scheme CCWidget
```

Without it the language server type-checks each file on its own, with no idea
that the rest of the target exists. `ForecastChart.swift` alone reports ten
errors — `Cannot find type 'Forecast' in scope` and friends — for code that
compiles cleanly. That is worse than no diagnostics at all: a wall of false
errors is a wall you learn to scroll past, and a real one arrives in the same
colour. The generated `buildServer.json` names this machine's DerivedData, so
it is gitignored rather than committed.

**Adding or moving a file means editing `project.yml`,** not clicking in
Xcode. Anything you add through the Xcode UI lands in a generated file and
disappears on the next generate. The build settings live in `project.yml`
too, with the reasoning next to them.

## Running the checks

```sh
xcodebuild -project CCWidget.xcodeproj -scheme CCWidget test
```

The checks live in `Tests/`, use swift-testing, and are grouped by area:
settings editing, installing, security, removal, the estimate, parsing, the
history and the exporter. They build into their own target and do not launch
the app — nothing they check needs it running.

**Adding a translation?** `TextMetricsTests` measures every localized caption
against the width its tile can give it, so a string that would truncate fails
before anyone sees it. The tightest budget is the small tile's header, where
Russian already uses 91 % of the space — that check exists because a caption
that fits in English and ends in an ellipsis in German has shipped here twice.

**The exporter is checked by running it.** `ExporterTests` installs the real
template through the real installer and feeds the result to a subprocess:
empty input, garbage, a megabyte, a payload with every optional field missing,
a symlink planted where the temporary file goes. Section 3 lists seven
guarantees for that script and every one of them is about behaviour, which is
why `py_compile` used to be the only check and proved nothing beyond the file
being syntactically Python.

Every one of them works **inside a temporary directory**. They must never
touch a real `~/.claude`. If you add a code path that reads or writes under
the user's home, it takes the root as a parameter — see SPEC section 5.2 for
why that rule exists, and `Tests/Sandbox.swift` for the stand-in root they all
share.

**Re-shooting the screenshots or the chart baselines?** Both the tool and the
check pin the render scale to 2 and convert to sRGB. `ImageRenderer.scale`
defaults to 1, not to the main display's scale — checked on a 1× monitor and a
2× built-in panel, and baselines taken with one primary verify unchanged with
the other. So the pin is not there to defend against your hardware; it is there
because without it every image comes out half size. If you regenerate a
baseline and every file shrinks, that is the pin gone rather than a real
difference.

Coverage, the same way CI measures it:

```sh
./Scripts/coverage.sh
```

It counts production code only and counts each file once — `Shared/` is
compiled into three targets, so the raw `xccov` report lists it three times.
There is no threshold: the figure and the list of files no check has ever
executed go in the CI job summary, and what to do about them is a decision,
not a default.

A check earns its place by testing the property, not a symptom of it. The one
that matters most here is in `SecurityTests`: an early version asked whether
the generated Python literal contained backslashes, which is a symptom, and it
would have passed the escaped slashes that actually broke the exporter. Asking
whether the literal parses back into the original path is the property, and it
caught the bug.

Two more tools, useful while working:

```sh
./.build/ccwidget-dump         # print the parsed snapshot and its diagnostics
./.build/ccwidget-screenshots  # re-shoot the README screenshots
```

Watching what the widget actually does:

```sh
log stream --predicate 'subsystem == "dev.illvminat.ccwidget"' --level info
```

## What a change should look like

- **Explain the why, not the what.** The diff already says what changed.
  Commit messages here are written in the imperative and spend their words on
  the reason, the constraint, or the failure that motivated the change.
- **Keep SPEC.md current.** It is the design document, not a historical
  artifact. If your change contradicts it, update it in the same commit.
- **No new dependencies in the app** without discussing it first. Nothing is
  linked that does not ship with Xcode, and that is worth keeping. Build-time
  tools are a separate question — XcodeGen is one, and it was still a
  deliberate decision rather than a convenience.
- **Swift 6, complete concurrency, zero warnings.** The build is warning-free
  today; keep it that way.
- **User-facing strings go through the string catalogs** in `App/Resources`
  and `Widget/Resources`. Data — formatted numbers, paths, project names —
  goes through `Text(verbatim:)` so it is not looked up as a translation key.
- **Nothing user-identifying in the log as `.public`.** Paths, project names
  and raw field values are `.private`.
- **A change to the widget's views is not done until a real machine says so.**
  `./Scripts/reinstall.sh` now waits and runs `Scripts/check-widget-health.sh`
  before it reports success. Every automated check in this repository runs in a
  test process where there is no WidgetKit; on 7 August 2026 the extension
  crashed on every render for five hours with all of them green, and because a
  crashing extension leaves its last good frame on the desktop, it looked like
  stale data rather than a crash.
- **A claim about someone else's system cites a source.** "WidgetKit reloads
  at most N times", "the sandbox allows this path", "the field is always an
  integer" — `SOURCES.md` lists what those claims are checked against, and
  says which of them have no source and are marked unverified instead. A
  reason that reads "because this other API works that way" is the shape of
  the mistake this is here to catch.

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
faster than large ones, and a change that comes with a check in `Tests/` gets
merged faster still.

If you are unsure whether something is wanted, open an issue before writing
the code. Nobody enjoys throwing away a weekend's work.

## Reporting a security problem

Do not open a public issue — see [SECURITY.md](SECURITY.md).
