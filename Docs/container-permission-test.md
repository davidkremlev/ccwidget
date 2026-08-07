# Container permission test

## Why this exists

The whole exchange in this project runs through one directory: the widget
extension's own container, at

    ~/Library/Containers/dev.illvminat.ccwidget.widget/Data/Library/Application Support/ccwidget/

The extension reads it as its own container, which the sandbox always allows.
Two other processes **write** into it, and neither owns it:

- **`CCWidget.app`**, when it installs the exporter and writes the first files;
- **`~/.claude/ccwidget-export.py`**, run by Claude Code on every status line
  update.

`SPEC` 2.2 records this as an accepted risk, and words it as something Apple
*might* tighten in a future release. Apple's documentation says otherwise. From
`~/Documents/refdocs/apple/security-sandbox-file-access.md`, section "Use files
in your app's container":

> In macOS 14 and later, the operating system uses your app's code signature to
> associate it with its sandbox container. If your app tries to access the
> sandbox container owned by another app, the system asks the person using your
> app whether to grant access.

and, in the same paragraph:

> The system also requests permission for an app to access files in another
> app's container if the app that's attempting to access the files doesn't have
> the app sandbox entitlement in its code signature.

`CCWidget.app` has no entitlements at all. By that text a permission prompt is
expected on the first write — yet on the developer's machine none has ever
appeared, across months of use.

Both things cannot be true of a first-ever run. One of them is about an account
where the answer was given long ago and is being remembered.

**This test decides which.** It cannot be run from the developer's account,
because that account has already answered whatever was asked.

---

## What you need

- A **new macOS user account** — System Settings → Users & Groups → Add User —
  or, better, a fresh virtual machine. A new account is enough for the
  container question; a VM additionally lacks Xcode and any prior TCC history.
- A built `CCWidget.app`. Build it in the developer account
  (`./Scripts/reinstall.sh` leaves one in `.build/dd/Build/Products/Release/`)
  and copy it to `/Users/Shared/` so the test account can reach it.
- Claude Code installed and usable from the test account's terminal.
- The macOS version, written down before you start: `sw_vers`.

Read the whole page before starting. Several steps are about noticing that
nothing happened, and that is hard to do retroactively.

---

## Before you touch anything

Record the starting state. Run in the **test account**:

```sh
sw_vers
ls -la ~/Library/Containers/ | grep -i ccwidget || echo "no ccwidget container — expected"
ls -la ~/.claude 2>/dev/null || echo "no ~/.claude — expected"
```

**Expected:** no container, and no `~/.claude` unless Claude Code has already
run here.

Open a second terminal window and leave this running for the whole test. It is
the only way to catch a prompt you dismissed by reflex:

```sh
/usr/bin/log stream --info --predicate \
  'process == "tccd" OR process == "containermanagerd" OR subsystem == "com.apple.TCC" OR eventMessage CONTAINS "ccwidget"' \
  | tee ~/Desktop/container-test-log.txt
```

Everything below refers to this stream as **the log window**.

---

## Step 1 — First launch, before any widget exists

Copy the app and launch it:

```sh
cp -R /Users/Shared/CCWidget.app /Applications/
open /Applications/CCWidget.app
```

Gatekeeper will refuse an ad-hoc-signed app that arrived by copy; if it does,
right-click → Open, or clear the flag with
`xattr -dr com.apple.quarantine /Applications/CCWidget.app` and note in your
record that you did.

**Expected:** the onboarding screen appears and says the widget has to be added
to the desktop first. **Do not add it yet.**

Record: did the app itself trigger any permission prompt at launch? Most likely
no — write "none" rather than leaving it blank.

## Step 2 — Add the widget, which is what creates the container

Right-click the desktop → Edit Widgets → find **Usage Widget for Claude Code**
→ drag the **small** size onto the desktop.

Then:

```sh
ls -la ~/Library/Containers/dev.illvminat.ccwidget.widget/Data/Library/Application\ Support/ 2>&1
```

**Expected:** the directory exists. It was created by the system, not by us —
that is the whole reason the installer refuses to run before this point.

Record: the timestamp on the container, and anything `containermanagerd`
printed in the log window while you dragged.

## Step 3 — The first write by the app *(the main question)*

Return to `CCWidget.app` and press the button that installs the exporter.

This is the moment the documentation predicts a prompt: a process with no
sandbox entitlement writing into a container that belongs to another bundle.

**Watch the screen, not the terminal.** A TCC prompt names the app and asks
about access to files. If one appears:

- **photograph or screenshot it before answering** — the exact wording matters,
  and it is not recoverable afterwards;
- note which application name it shows (`CCWidget`? the extension? something
  generic);
- answer **Allow**, then continue.

If none appears, wait five seconds and note "no prompt".

Then, in the first terminal:

```sh
ls -l ~/Library/Containers/dev.illvminat.ccwidget.widget/Data/Library/Application\ Support/ccwidget/
ls -l ~/.claude/ccwidget-export.py
```

**Expected if permission was granted or never asked:** the `ccwidget/`
directory exists and the exporter file is present and executable.

**If the write was refused,** the app should say so on screen rather than
silently doing nothing. Record what it said, word for word, and then:

```sh
/usr/bin/log show --last 5m --info --predicate 'process == "CCWidget"' --style compact | tail -40
```

Look for `Operation not permitted`, `deny file-write`, or a `tccd` decision.
Copy the lines into your record.

## Step 4 — The first write by the exporter

The exporter is a different process with a different signature: Python, run by
Claude Code, not by us. The documentation's rule is about the *accessing*
process, so this may behave differently from step 3.

In the test account's terminal:

```sh
claude
```

Send one short message, so a status line update happens, then quit.

```sh
ls -l ~/Library/Containers/dev.illvminat.ccwidget.widget/Data/Library/Application\ Support/ccwidget/
```

**Expected:** `snapshot.json` exists and its timestamp is seconds old.

Record: whether a prompt appeared for **Terminal** (or iTerm, or whichever app
runs your shell) rather than for CCWidget — that is the likely form here, since
TCC asks on behalf of the responsible process.

If `snapshot.json` did not appear:

```sh
/usr/bin/log show --last 5m --info --predicate \
  'eventMessage CONTAINS "ccwidget" OR eventMessage CONTAINS "deny"' --style compact | tail -40
python3 ~/.claude/ccwidget-export.py < /dev/null; echo "exit: $?"
```

The second command runs the exporter by hand with empty input; it should exit
quietly. Any traceback or permission error goes into the record verbatim.

## Step 5 — Does the widget actually show the numbers

Look at the widget on the desktop. **Expected:** within a minute it shows
percentages rather than the "waiting for data" state.

This is the end-to-end answer: it means a process outside the container wrote
into it and the extension read what was written.

## Step 6 — The refusal path *(optional, and destructive to the test account)*

Only if step 3 produced a prompt. Reset the decision and repeat, answering
**Deny** this time:

```sh
tccutil reset SystemPolicyAllFiles dev.illvminat.ccwidget
tccutil reset All dev.illvminat.ccwidget
```

Then repeat step 3 and record what the app shows the person when the write is
refused. This tells us whether the failure is legible or looks like "no data".

---

## What to write down

Even when everything works, the record is the result. For each step:

| | |
|---|---|
| macOS version and build | from `sw_vers` |
| Account type | new user account / fresh VM |
| Prompt at step 3 | none, or screenshot + exact wording + which app it named |
| Prompt at step 4 | none, or screenshot + which app it named |
| Files after step 3 | output of the two `ls -l` commands |
| Files after step 4 | output of `ls -l` |
| Widget after step 5 | numbers / waiting / setup screen |
| Log file | `~/Desktop/container-test-log.txt`, keep it whole |

**"Nothing happened" is a result, and the most likely one.** If no prompt
appears anywhere, that means the documented behaviour does not apply to this
shape of access — and `SPEC` 2.2 should say so with this test as its evidence,
instead of describing a risk that may already be settled. Write the negative
result as carefully as you would write a prompt: which steps ran, what the
system version was, and that the log window stayed silent throughout.

The one thing that would be worth an immediate report is a prompt naming an
application the person has no reason to trust — the extension, or a bare bundle
identifier — because that is what a first-time user would see and refuse.

---

## Putting the account back

The clean way, if this was a throwaway account or VM: **delete the account**
(System Settings → Users & Groups → the account → Remove), or discard the VM
snapshot. Nothing below is needed then.

If you want to keep the account:

```sh
# 1. Remove the widget from the desktop first — right-click it → Remove Widget.
#    The container survives this; the system owns it.

# 2. Undo the installer's edit to the Claude Code config.
#    Do this from the app: the uninstall button removes only its own statusLine
#    key and leaves neighbouring keys alone. Prefer it to editing by hand.
open /Applications/CCWidget.app

# 3. Remove the app and its files.
rm -rf /Applications/CCWidget.app
rm -f ~/.claude/ccwidget-export.py
rm -rf ~/Library/Containers/dev.illvminat.ccwidget.widget

# 4. Clear any TCC decisions this test created.
tccutil reset All dev.illvminat.ccwidget

# 5. Check nothing is left running.
pgrep -fl CCWidget || echo "nothing running — expected"
```

Leave `~/.claude` itself alone unless you created it for this test: it belongs
to Claude Code, not to us.
