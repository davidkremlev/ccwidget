# ccwidget — Usage Widget for Claude Code

A macOS desktop widget showing how much of your Claude subscription you have
spent, how full the context window is, and when the weekly quota runs out.

> **Works with the terminal version of Claude Code only.**
> The widget is fed by the Claude Code status line, which exists solely in the
> CLI. If you use Claude only through the desktop app or the web, the status
> line never runs, nothing is ever written, and the widget stays empty
> forever — not "outdated", but blank. There is no workaround today. Removing
> this limitation is the top open question in [SPEC.md](SPEC.md#14-открытые-вопросы).

Everything else on this page assumes `claude` runs in your terminal.

| | |
|---|---|
| ![Medium widget, dark](Docs/screenshots/medium-dark.png) | ![Small widget, dark](Docs/screenshots/small-dark.png) |

<details>
<summary>Large size with the forecast, and everything in light mode</summary>

| | |
|---|---|
| ![Large widget, light](Docs/screenshots/large-light.png) | ![Large widget, dark](Docs/screenshots/large-dark.png) |
| ![Medium widget, light](Docs/screenshots/medium-light.png) | ![Small widget, light](Docs/screenshots/small-light.png) |

</details>

Screenshots are real data from a working session, not mock-ups. Re-shoot them
with `./.build/ccwidget-screenshots Docs/screenshots -AppleLocale en_US -AppleLanguages "(en)"`.

---

## What it shows

Three rows, all in the same direction: **how much has been consumed.** More is
always worse. The bar always matches the number next to it.

| Row | What it measures | Scope |
|---|---|---|
| `5-hour used` | the rolling five-hour limit | your account |
| `Week used` | the seven-day limit | your account |
| `Context used` | how full the current context window is | one Claude Code session |

**`Context used` is not a subscription limit.** This is the row people
misread. The first two are quotas Anthropic enforces: hit 100% and Claude
stops answering until the window resets. The third is the size of the
conversation currently loaded into the model — it resets when you run
`/clear`, costs you nothing, and blocks nothing. It is here because past
roughly 70% the model starts losing details from the beginning of the
conversation, which is worth seeing before it happens. That is why its colour
turns red at 70% while the limits stay yellow until 81%.

Scope matters too. The two limits belong to your account and are identical no
matter which project you are working in. Context, cost and cache ratio belong
to a single Claude Code session — the one that redrew its status line last.
With several sessions open, those three values flicker between them, which is
why the widget labels them: the project name sits next to the context row, and
the footer says `this session`.

The large size adds an estimate of when the weekly quota runs out:
least-squares regression over the current week's history, weighted towards
recent usage. It is built to refuse rather than to guess, and it has three
answers instead of two:

- **A date** — but only when there are at least ten points spanning at least
  two hours, the line fits them (R² ≥ 0.7), and the date lands within ten
  times the span the points cover. Extrapolating a day of usage across a week
  is arithmetic, not knowledge.
- **A rate with no date** — "~0.7 %/h". Right after the weekly reset the
  reset is nearly seven days out and no honest date can be named for about
  seventeen hours, but the pace is already measurable, and silence for
  seventeen hours reads as broken.
- **Nothing** — too few points, too short a span, or a line that does not
  describe the data. A wrong estimate is worse than none.

## Trusting the numbers

The status line format is undocumented, so the numbers deserve verification.
There is exactly one independent source: the **Usage panel in the Claude app.**

Both show consumption, so the check is one glance with no arithmetic:

| Widget row | Usage panel | Should match |
|---|---|---|
| `5-hour used` | **Current session** | yes, digit for digit |
| `Week used` | **All models** | yes, digit for digit |
| `Context used` | — | not shown there; it is not a subscription limit |
| — | **Fable** | not shown here; the status line has no per-model breakdown |

Two names are confusing and worth stating plainly. Anthropic's **"Current
session"** means the five-hour account window, not your conversation — which
is exactly why this widget says `5-hour` instead of `Session`. And **"All
models"** is the weekly window.

A one-percent difference is fine: the exporter rounds fractional values. More
than that is a bug — please [open an issue](../../issues).

### The window and the widget can hold different snapshots

While an agent is working, the window may show figures the widget has not
caught up with yet. That is expected and it is not a bug.

The window reads the file the moment it changes; the widget is redrawn only
when macOS is asked to reload it, and that is rationed so the reload budget
lasts. So the widget can be holding a snapshot up to a minute old.

What does **not** differ any more is what they say about the snapshot they are
holding. Both print the time it was taken — *updated at 11:50* — rather than
how long ago that was, and both hand the countdown to a reset straight to the
system rather than computing it. Neither is doing arithmetic the other could
do differently.

The percentages are whole numbers and move slowly, so in practice they agree.
In the minute where one of them crosses a whole point they can differ, for the
reason above and no longer. The other places it shows are the exact token count
on the large tile and the *Snapshot* row under Details in the window.

Worth an issue if the widget stays behind for more than a minute while Claude
Code is running.

## Languages

The interface is in English, German, Spanish, Japanese, Russian and Simplified
Chinese, and follows your system language.

> **Four of those six have never been read by a native speaker.** German,
> Spanish, Japanese and Simplified Chinese are one developer's best effort with
> a dictionary and a careful ear. English and Russian are first-language work.
>
> The row captions were already rewritten once, after reading them aloud caught
> translations that were word-for-word correct and that nobody says — German
> `Woche genutzt` and Spanish `Semana usada` both meant "a week that was used".
> There are almost certainly more of those.
>
> **If you read one of the four, corrections are the single most welcome
> contribution to this project right now.** One line in an issue is enough — no
> pull request needed, no need to know Swift, and the string catalogs are plain
> JSON if you would rather edit them directly. See
> [`Docs/localization-review.md`](Docs/localization-review.md) for the exact
> strings and what each one is for.

## Requirements

- macOS 14 or later (the oldest version the checks run on)
- Claude Code, terminal version, used at least once
- A Claude subscription that reports rate limits

**What "macOS 14 or later" is worth.** CI builds the app and runs the checks
on macOS 14 and on macOS 26, so the code compiles and its logic runs on both.
That is the whole of it. The widget itself — WidgetKit, the timeline, the
three sizes on a real desktop — has only ever been run by hand, on macOS 26.
There is no automated way to put a widget on a desktop, and the view code has
no test coverage at all. If you are on 14 or 15 and something looks wrong,
that is worth an issue: you would be the first to look.

## Installing

There are no releases yet — no signed build, no Homebrew formula. The only
way to run this today is to build it, which means **Xcode 16 or later** and
**XcodeGen**, which generates the Xcode project from `project.yml`.

```sh
brew install xcodegen
git clone https://github.com/illVminat/ccwidget.git
cd ccwidget
./Scripts/reinstall.sh
```

`reinstall.sh` is a **development script, not an installer.** It generates the
project, removes `/Applications/CCWidget.app` if present, copies a fresh build
over it, and restarts `chronod` — the system daemon behind every widget on your
Mac. The restart is unavoidable (see Development below) and harmless: the
system brings it straight back and all widgets redraw. Read the script before
running it; it is sixty lines.

Then, in this order:

1. **Add the widget to your desktop first** — right-click the desktop, choose
   *Edit Widgets*, find *Usage Widget for Claude Code*. This step cannot be skipped:
   the exchange directory is created by the system when the widget extension
   first runs, and the app deliberately refuses to create it itself.
2. Open the app and press **Set up automatically.** It writes the exporter to
   `~/.claude/ccwidget-export.py` and adds one `statusLine` key to
   `~/.claude/settings.json`. A timestamped copy of your settings is saved
   first, and an existing status line is shown to you before it is replaced.
   Normally only that one key changes and your indentation and key order
   survive; if the file cannot be patched in place — malformed JSON, comments
   — it is rebuilt instead, and the app tells you so rather than hiding it.
3. Send any message in Claude Code. The first numbers appear within seconds.

Prefer not to let an app edit your config? The setup screen has **Show manual
instructions** with the exact lines to paste.

**On a build you did not compile yourself** — a copy from someone else, or a
future release — macOS will refuse to open it. The app is ad-hoc signed and
not notarized, so Gatekeeper treats it as untrusted. A locally built app opens
without complaint. This is the main thing standing between the project and a
real release; see SPEC.md section 14.

Checked rather than assumed, by quarantining a copy the way a download would
be. The dialog says *"'CCWidget.app' Not Opened — Apple could not verify
'CCWidget.app' is free of malware that may harm your Mac or compromise your
privacy"*, and it offers **Move to Trash** or **Done** — there is no "Open
Anyway" in it. On current macOS that button lives in **System Settings →
Privacy & Security**, below the message about the blocked app, and appears
only after you have tried to open it once. Worth knowing before you conclude
the app is broken.

## When the numbers stop moving

Claude Code is running, you are working, and the widget has not changed in a
while. On screen that looks exactly like Claude Code not running at all — the
numbers simply age. These are different problems and there is one command that
tells them apart.

Build `ccwidget-dump` with the command under [Development](#development) — one
copy of it, so it cannot drift from the one CI runs — and then:

```sh
./.build/ccwidget-dump
```

**If it starts with `!! The exporter is writing nothing`**, the status line is
running and choosing not to write:

```
!! The exporter is writing nothing.
   since:   3 Aug 2026 at 20:48:30
   for:     8 min
   reason:  the status line sent no rate_limits
```

That happens when Claude Code sends a redraw with no rate limits in it. Every
session begins with one such redraw, and the notice clears itself the moment
you send your first message — so seeing it for a second or two after starting
Claude Code is normal.

A notice that outlives that, minutes into a working session, is something we
have never seen and would like to: please [open an issue](../../issues) with
the *since* and *for* lines. It means the status line has stopped sending
limits, and the numbers you are looking at are as old as the notice says.

**If there is no such line and the snapshot is simply old**, nothing is writing
at all. The usual causes, in the order worth checking:

- Claude Code is the desktop app rather than the terminal one — the status line
  only runs in the terminal, and this widget has no other source.
- The `statusLine` key in `~/.claude/settings.json` no longer points at
  `~/.claude/ccwidget-export.py`. The app's window says **Setup needed** when
  that is the case.
- The exporter file was deleted or replaced. The window's **Details** says
  *modified since installation* or *not installed*.

**If the numbers are current but the widget is showing older ones**, that is
expected up to a minute — the widget is redrawn at most once a minute so the
reload budget lasts. See *The window and the widget can hold different snapshots*
above.

## Removing it

Either way undoes the same things.

In the app: **Remove…**, then choose whether to keep the collected history.

Or without the app:

```sh
./Scripts/uninstall.sh            # keep history
./Scripts/uninstall.sh --purge    # remove history, container and the app
./Scripts/uninstall.sh --dry-run  # show what would happen, change nothing
```

Removal deletes the `statusLine` key rather than restoring your old
`settings.json` wholesale — you may have changed other keys since installing,
and rolling the file back would take those edits away from you. A backup is
still written first.

The app bundle and the extension's container are not removed unless you pass
`--purge`, and the widget itself has to be dragged off the desktop by hand.

## How it works

```
Claude Code ──status line JSON──▶ ccwidget-export.py ──▶ snapshot.json
                                                        history.jsonl
                                                             │
                                              widget extension container
                                                             │
                                                     WidgetKit timeline
```

The exporter runs on every status line redraw, writes atomically, and always
exits 0 — a broken exporter must never break your prompt. It prints nothing,
which means **your status line goes blank**: this project takes the line over
rather than sharing it. Composing with an existing status line is planned but
not written.

**How fast the widget updates depends on whether the app window is open.**
With it open, a watcher notices new data and refreshes the widget within a
minute. With it closed — the normal case after setup — nothing pushes updates,
and WidgetKit comes back on its own roughly every half hour. The numbers are
never wrong, only older than they could be, and the widget always says how old
they are. A proper background agent is version 1.1.

**Everything happens on your machine.** There is no network code in this
project: nothing is uploaded, no telemetry is collected, and no account is
needed beyond the one Claude Code already uses. The widget never talks to
Claude at all — it reads a file that Claude Code itself hands to a status
line command you configured, and it holds no credentials of any kind. For a
tool whose whole job is watching how much of your quota is left, that is
worth knowing before you install it.

Data is exchanged through the widget extension's own sandbox container rather
than an App Group. App Groups do not work for widget extensions under ad-hoc
signing, and requiring a paid Apple Developer membership from everyone who
builds from source was not acceptable. The trade-offs are written up in
[SPEC.md](SPEC.md), section 2.2.

## Development

The console tools are not built by `reinstall.sh` — build them when you need
them:

```sh
# print the parsed snapshot and its parse diagnostics
swiftc -swift-version 6 -target arm64-apple-macos14.0 \
    Shared/Snapshot.swift Shared/SnapshotStore.swift Shared/Formatters.swift \
    Shared/Diagnostics.swift Shared/AgeClock.swift \
    Tools/ccwidget-dump/main.swift -o .build/ccwidget-dump

# replay a history.jsonl through the estimate: what the widget would have
# shown, for how long, and at every change of state
swiftc -swift-version 6 -target arm64-apple-macos14.0 \
    Shared/Snapshot.swift Shared/SnapshotStore.swift Shared/Formatters.swift \
    Shared/Diagnostics.swift Shared/AgeClock.swift \
    Shared/HistoryStore.swift Shared/Forecast.swift \
    Tools/ccwidget-replay/main.swift -o .build/ccwidget-replay

# re-shoot the screenshots, or render any view without putting a widget on a
# desktop. Needs the views as well as the shared code, which is why the list
# is longer.
swiftc -swift-version 6 -target arm64-apple-macos14.0 \
    Shared/*.swift \
    Widget/Provider.swift Widget/Components.swift Widget/ForecastChart.swift \
    Widget/SmallView.swift Widget/MediumView.swift Widget/LargeView.swift \
    Tools/ccwidget-screenshots/main.swift -o .build/ccwidget-screenshots
```

**Render in the language you are changing.** The tool takes the locale from the
arguments, and a layout that fits in English can fail in Russian or German:

```sh
./.build/ccwidget-screenshots /tmp/shots -AppleLocale ru_RU -AppleLanguages "(ru)"
```

CI builds the first two of these on every push. The third is not built there —
so unlike the others, it can rot unnoticed — and the flags differ: CI adds
`-strict-concurrency=complete`, which these lines omit. Nothing compares the two,
so treat this block as a copy that can drift rather than as the same commands.

If the icon stays a grey placeholder after the first install, that is macOS's
icon cache rather than the build. It survives reinstalling, `lsregister` and a
`chronod` restart; what clears it is:

```sh
sudo rm -rf /Library/Caches/com.apple.iconservices.store
sudo find /private/var/folders -name com.apple.dock.iconcache -delete
killall Dock
```

Before reaching for that, check the bundle actually carries the icon — the two
products are compiled by `actool`, not copied, and a build says nothing either
way. The second command renders the standalone copy to a PNG you can open:

```sh
ls /Applications/CCWidget.app/Contents/Resources/Assets.car \
   /Applications/CCWidget.app/Contents/Resources/CCWidget.icns
sips -s format png /Applications/CCWidget.app/Contents/Resources/CCWidget.icns \
     --out /tmp/ccwidget-icon.png && open /tmp/ccwidget-icon.png
```

If those show the ring and the surfaces still show a square, it is the cache.

Watching what the widget actually does:

```sh
log stream --predicate 'subsystem == "dev.illvminat.ccwidget"' --level info
```

`killall chronod` at the end of the install script is not optional: the widget
daemon survives bundle replacement and otherwise keeps running your previous
build, which looks exactly like your changes not applying.

[CONTRIBUTING.md](CONTRIBUTING.md) has the rest. [SPEC.md](SPEC.md) is the
design document and is kept current — it records the failures too, which is
usually where the reasoning lives. It is written in Russian; translating it is
on the list.

## Not affiliated with Anthropic

This is an independent project. It is not affiliated with, sponsored by, or
endorsed by Anthropic.

Claude and Claude Code are trademarks of Anthropic, PBC. They are used here
descriptively and only to state what this widget is compatible with. No
claim to those marks is made or implied, and no association with Anthropic
should be inferred from the name.

## Licence

[MIT](LICENSE). Copyright © 2026 illvminat.

MIT matches what the surrounding ecosystem uses — ccusage, ccstatusline and
neighbours — so code can be borrowed in either direction without a licence
audit, and the whole text fits on one screen.
