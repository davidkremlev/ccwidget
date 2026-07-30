# Clean-account test

Everything in this project has so far been verified from one account, on one
machine, with the developer's toolchain already installed and the widget
already registered. That account cannot test the things that break for
everybody else: a missing interpreter, a first-ever widget registration, a
`~/.claude` that does not exist yet, a Gatekeeper prompt on an app that was
never built locally.

This is the list for that. Run it on a **new macOS user account** — System
Settings → Users & Groups → Add User. A fresh virtual machine is better still,
because it also lacks Xcode.

Record the result of each step. Where a step says *"expected"*, anything else
is a finding worth reporting.

---

## Before you start

On the clean account, confirm the starting state:

```sh
ls -la ~/.claude 2>&1              # expected: No such file or directory
ls -la ~/Library/Containers | grep ccwidget   # expected: nothing
xcode-select -p 2>&1               # note whether Command Line Tools exist
/usr/bin/python3 -V 2>&1           # note whether this prompts to install CLT
```

The last two matter: on an account without Command Line Tools,
`/usr/bin/python3` is a stub that pops an installer dialog instead of running.
That is precisely the case the developer's machine cannot reproduce.

---

## 1. Build from a clean clone

**Do:** clone the repository into a fresh directory and run
`./Scripts/reinstall.sh`.

**Expected:** the build completes with no errors and no warnings, the app
appears in `/Applications`, and it launches. If Xcode is missing entirely the
build fails — note the error text, because that text is what a new contributor
sees first.

**Also worth noting:** whether Gatekeeper blocks the app on first launch, and
what the dialog says. An ad-hoc signed app built locally usually opens without
complaint, but a copied one does not — see step 9.

---

## 2. First launch with no Claude Code installed

If Claude Code is not installed on the clean account, launch the app now.

**Expected:** the onboarding screen says Claude Code was not found, explains
that the terminal version is required, and offers a link. It must not offer to
install anything, and must not crash.

Then install Claude Code and press **Check again**.

**Expected:** the screen advances to the install step without a restart.

---

## 3. Setup refused before the widget exists

Do **not** add the widget yet. Open the app and look at the install step.

**Expected:** it says to add the widget to the desktop first, and explains why.
The **Set up automatically** button must not perform an install. Confirm
nothing was written:

```sh
ls ~/.claude/ccwidget-export.py 2>&1                    # expected: not found
ls -d ~/Library/Containers/dev.illvminat.ccwidget.widget 2>&1  # expected: not found
```

This is the step most likely to be wrong, because it depends on ordering that
a machine with the widget already installed can never exercise.

---

## 4. Add the widget

Right-click the desktop → **Edit Widgets** → find *Usage Widget for Claude Code* →
add the **medium** size.

**Expected:** the widget appears and shows *"No data yet"* with an instruction
to launch Claude Code — not a blank rectangle, not a placeholder with fake
numbers, not an error.

Confirm the system created the container:

```sh
ls -ld ~/Library/Containers/dev.illvminat.ccwidget.widget/Data
```

**Expected:** it exists, mode `drwx------`.

---

## 5. Interpreter detection

Return to the app.

**Expected:** the install step now shows a line naming the interpreter it will
use, and the **Set up automatically** button is enabled.

**On an account without Command Line Tools:** expected instead is a warning
that no working `python3` was found, naming `xcode-select --install`, with the
button **disabled**. Verify it is genuinely disabled, then install the tools,
reopen the app, and confirm the warning clears.

---

## 6. Install

Press **Set up automatically**.

**Expected:** the screen moves to *"Launch Claude Code and send any message"*
and names the backup file it created.

Verify what landed on disk:

```sh
ls -ld ~/.claude                       # expected: drwx------  (we created it)
ls -l ~/.claude/ccwidget-export.py      # expected: -rwxr-xr-x
head -1 ~/.claude/ccwidget-export.py    # expected: an absolute path, not /usr/bin/env
grep GROUP_DIR ~/.claude/ccwidget-export.py | head -1
cat ~/.claude/settings.json
ls ~/.claude/settings.json.bak-*
```

**Expected:** `settings.json` contains a `statusLine` key pointing at the
script, and — if the file already existed — every other key is untouched, with
its original indentation and key order.

---

## 7. First data

Run `claude` in a terminal and send any message.

**Expected:** within seconds the app screen shows the first live numbers, and
the widget on the desktop fills in. Note how long this actually took.

Then check the numbers against the **Usage panel** in the Claude app:

| Widget | Usage panel |
|---|---|
| `5-hour used` | *Current session* |
| `Week used` | *All models* |

**Expected:** they match digit for digit, or differ by at most one percent.

---

## 8. Existing status line is not silently replaced

Only if the clean account already had a status line configured — otherwise
create one first, pointing at any harmless script.

**Expected:** the install step shows the existing command before you press
anything, and the backup restores it exactly.

---

## 9. Copied app, not built app

Copy `/Applications/CCWidget.app` from the clean account to another machine, or
zip and unzip it, then launch.

**Expected:** Gatekeeper blocks it, because the app is ad-hoc signed and not
notarized. **Note the exact wording of the dialog** — that dialog is what
every user who downloads a release will see, and the README currently says
nothing about it.

---

## 10. Removal

There is no supported removal path yet — this step is here to measure how bad
that is. Try to undo the installation using only what the project documents.

Record: what you had to do by hand, what you could not find, and whether
`settings.json` ended up back the way it started.

---

## What counts as success

- Steps 1–8 behave as described, with no crash and no silent failure.
- Nothing is written before step 6.
- The numbers in step 7 match the Usage panel.
- Steps 9 and 10 produce written notes rather than a pass or a fail; both are
  known gaps, and the point is to learn exactly how they look to a stranger.

## What to send back

The output of the commands above, the wording of any dialog that appeared, and
the time between pressing **Set up automatically** and the widget filling in.
Screenshots of anything that looked wrong are worth more than a description.
