# ccgauge — Gauge for Claude Code

A macOS desktop widget showing how much of your Claude subscription you have
spent, how full the context window is, and when the weekly quota runs out.

> **Works with the terminal version of Claude Code only.**
> The widget is fed by the Claude Code status line, which exists solely in the
> CLI. If you use Claude only through the desktop app or the web, the status
> line never runs, nothing is ever written, and the widget stays empty
> forever — not "outdated", but blank. There is no workaround today. Removing
> this limitation is the top open question in [SPEC.md](SPEC.md#14-открытые-вопросы).

Everything else on this page assumes `claude` runs in your terminal.

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

The large size adds a forecast: least-squares regression over the current
week's history, weighted towards recent usage. It refuses to guess — fewer
than five data points, less than thirty minutes of spread, or flat usage and
it shows a dash instead of a number. A wrong forecast is worse than none.

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

## Requirements

- macOS 14 or later (desktop widgets arrived there)
- Claude Code, terminal version, used at least once
- A Claude subscription that reports rate limits

## Installing

Not published yet. Build from source:

```sh
git clone <this repository>
cd ccgauge
./Scripts/reinstall.sh
```

The script builds, installs to `/Applications`, and restarts the widget
daemon. Then:

1. **Add the widget to your desktop first** — right-click the desktop, choose
   *Edit Widgets*, find *Gauge for Claude Code*. This step cannot be skipped:
   the exchange directory is created by the system when the widget extension
   first runs, and the app deliberately refuses to create it itself.
2. Open the app and press **Set up automatically.** It writes the exporter to
   `~/.claude/ccgauge-export.py` and adds one `statusLine` key to
   `~/.claude/settings.json`. Only that key changes — indentation and key
   order are preserved, and a timestamped copy is saved next to the file
   first. If you already have a status line configured, it is shown to you
   before anything is replaced.
3. Send any message in Claude Code. The first numbers appear within seconds.

Prefer not to let an app edit your config? The setup screen has **Show manual
instructions** with the exact commands.

## How it works

```
Claude Code ──status line JSON──▶ ccgauge-export.py ──▶ snapshot.json
                                                        history.jsonl
                                                             │
                                              widget extension container
                                                             │
                                                     WidgetKit timeline
```

The exporter runs on every status line redraw, writes atomically, and always
exits 0 — a broken exporter must never break your prompt. It prints nothing:
your status line stays empty and the widget is the only consumer.

Data is exchanged through the widget extension's own sandbox container rather
than an App Group. App Groups do not work for widget extensions under ad-hoc
signing, and requiring a paid Apple Developer membership from everyone who
builds from source was not acceptable. The trade-offs are written up in
[SPEC.md](SPEC.md), section 2.2.

Nothing leaves your machine. There is no network code in this project.

## Development

```sh
./Scripts/reinstall.sh        # build, install, restart the widget daemon
./.build/ccgauge-dump         # print the parsed snapshot
./.build/ccgauge-selftest     # installer and settings-editor checks
```

`killall chronod` at the end of the install script is not optional: the widget
daemon survives bundle replacement and otherwise keeps running your previous
build, which looks exactly like your changes not applying.

[SPEC.md](SPEC.md) is the design document and is kept current — it records the
failures too, which is usually where the reasoning lives.

## Licence

Not chosen yet — see the discussion below before opening a pull request.
