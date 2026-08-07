# Read cold by an outsider, 7 August 2026

A second reviewer, separate model, clean context, told only what a newcomer
would learn from the README. Asked not to hunt defects but to report the
experience of meeting the project for the first time: what is unclear, what
looks suspicious, what is missing, what they did not believe, and whether they
would install it.

Received as written; nothing acted on.

---

## First impression

> This is the most self-aware README I have read in a long time. The
> terminal-only limitation is in the first paragraph, before the screenshots.
> The install section calls its own installer "a development script, not an
> installer". The requirements section spends a paragraph deflating its own
> "macOS 14 or later" claim. Almost every question I formed while reading was
> answered two paragraphs later, usually more bluntly than I would have put it.
> That earns a lot of trust — and it also sets a very high bar that the project
> then occasionally fails to clear, which is where the rest of this report
> lives.

## What is unclear

**The app itself is never introduced.** The README explains the widget, the
exporter and the snapshot, then starts referring to "the window" as if the
reader knew what it was. The reviewer had to infer from scattered mentions that
`CCWidget.app` is a companion status window with a live view, a Details pane
and a Remove button — "that surface is a third of the product and the README
never once shows it or names it." No screenshot of the window, none of
onboarding, "even though step 2 of installation asks me to trust that screen
with edits to my `~/.claude/settings.json`."

**`ccwidget-screenshots` has no build command anywhere.** README and
CONTRIBUTING both tell you to run it; the Development section gives `swiftc`
lines for `ccwidget-dump` and `ccwidget-replay` and not for this one; CI builds
only those two. "So the tool that produced the images at the top of the README
has no build instructions anywhere in the repository. I looked; I gave up."

**A cross-reference to a section that no longer exists.** "When the numbers stop
moving" points at *"The window and the widget can be a minute apart"*; the
section is now called "The window and the widget can hold different snapshots".

**The honest caveats about the forecast live only in Russian.** SPEC 14 admits
the estimate's live behaviour rests on one person's 118-hour history that never
approached exhaustion, and that the R² gates mostly fire on light weeks rather
than dangerous ones. "An English-only reader never learns the forecast has
effectively one real week of validation behind it… the confidence is in
English, the doubt is in Russian."

## What looks suspicious

**The screenshots contradict the text beside them.** README: *"Both print the
time it was taken — updated at 11:50"*. Every screenshot footer reads **"in 0
seconds"**. "For a project whose creed is 'documentation does not diverge from
code', the front-page images diverging from the adjacent paragraph is the
single most jarring thing I found."

**"Real data from a working session, not mock-ups" is narrower than it looks.**
They are renders from a tool, not desktop captures — and the project's own audit
says two Apple sources disagree about whether macOS widgets get accented
rendering, which would flatten the gauge colours. "So the images showing
coloured bars are exactly the thing the project privately does not consider
verified."

**The architecture stands on a floor Apple never promised.** The candour about
writing into another bundle's container is respected, but "it is still a
load-bearing hack… If I install this, I am betting on `containermanagerd`'s
continued indifference."

**Your status line goes blank, and you learn that in "How it works".** For an
audience already running ccusage or ccstatusline, "that is not a footnote, it is
a dealbreaker-grade cost, and it sits in the seventh section rather than beside
the terminal-only warning at the top."

**One repository, zero external eyes.** "Everything about the project says one
meticulous person talking to themselves at very high quality… every verification
in the repo was designed and executed by the same mind that wrote the code."

## What is missing

- A picture of the app window and of onboarding — "the surface that asks for the
  most trust is the only one never shown."
- A build command for `ccwidget-screenshots`.
- An English SPEC. CONTRIBUTING tells contributors to read SPEC before any
  non-trivial change; "for most of the audience that instruction is
  unexecutable."
- Issue templates, for a project that asks for structured reports.
- Releases — admitted openly.
- **Any note on multi-machine use.** Quotas are account-wide, but each widget
  sees only its own machine's history, so the forecast fits half the real usage.
  "It is the first practical question I had as a would-be user."

## What they did not believe

**"The same commands run in CI on every push."** Checked and not literally true:
CI compiles the tools with `-strict-concurrency=complete`, the README's commands
omit it. "Two copies, already drifted, under a sentence claiming there is one
copy so drift is impossible."

**"There is no network code in this project"** — believed, and the reviewer said
why: they grepped themselves, then found CI doing the identical grep as a
permanent check. "A claim shipped with its own enforcement. More of the README's
claims should be like this one."

**The estimate's reliability as an English reader receives it.** "The README
presents a tuned instrument and the Russian SPEC presents a hypothesis tested
against one uneventful week. The Russian version is the one I believe."

## Would they install it

**Yes, conditionally.** The security posture "survived my reading better than
almost any hobby tool I have inspected cold" — symlink refusal, the 1 MB cap
with the gigabyte incident in the comment, atomic writes, always exiting 0,
preferring root-owned `/usr/bin/python3`, 8-character session IDs, no full
paths.

Two gates: losing the status line to a blank ("if I used ccstatusline or any
custom line, that alone is a no until the planned composition ships"), and the
container-write hack meaning an OS update can silently orphan the pipeline.
What would make it unconditional: **status line pass-through, a notarized
release, and one screenshot set that matches the shipped code.**

## Their closing note

> The strange overall verdict: this project's documentation is so unusually
> honest that its few overstatements — the "in 0 seconds" screenshots beside a
> sentence they contradict, the "one copy" claim that is two copies, the
> confidence gradient between the English README and the Russian SPEC — stand
> out the way a single wrong note does in an otherwise clean performance. In an
> average repository none of them would be worth writing down.
