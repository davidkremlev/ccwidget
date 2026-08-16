#!/bin/bash
#
# Undoes a ccwidget installation.
#
# It mirrors the "Remove…" button in the app and exists as a fallback: if the
# app will not launch, or has already been deleted, the button is gone while
# the traces in the config remain. A tool that edits someone else's file and
# registers an auto-running command has to be able to remove itself without
# itself.
#
# The statusLine key is deleted surgically rather than rolled back from a
# backup: other keys may have changed between install and removal, and rolling
# the whole file back would take those edits away.
#
# What counts as ours is an exact match on `statusLine.command`, the same test
# the app makes (`Installer.statusLineState`). It used to be a grep of the
# whole file for the substring `ccwidget-export.py`, which called any status
# line ours as long as the exporter was mentioned anywhere — including by a
# hook, or by a wrapper of the user's own that chains it. Removal is the one
# operation where guessing wrong destroys something, and it was the operation
# doing the guessing. Checked by Scripts/check-uninstall.sh.
#
#   ./Scripts/uninstall.sh              # undo the install, keep the history
#   ./Scripts/uninstall.sh --purge      # remove the history and the app too
#   ./Scripts/uninstall.sh --dry-run    # only show what would happen
#
set -euo pipefail

WIDGET_ID="dev.illvminat.ccwidget.widget"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
EXPORTER="$CLAUDE_DIR/ccwidget-export.py"
INTEGRITY="$CLAUDE_DIR/.ccwidget-export.sha256"
EXCHANGE="$HOME/Library/Containers/$WIDGET_ID/Data/Library/Application Support/ccwidget"
CONTAINER="$HOME/Library/Containers/$WIDGET_ID"
APP="/Applications/CCWidget.app"

PURGE=0
DRY=0
for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        --dry-run) DRY=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

run() {
    if [ "$DRY" -eq 1 ]; then echo "    [dry run] $*"; else "$@"; fi
}

# A heading for a step that only happens for real. Without the prefix a dry
# run announces "Removing the exporter" in the same words as a removal.
step() {
    if [ "$DRY" -eq 1 ]; then echo "==> [dry run] $*"; else echo "==> $*"; fi
}

VERDICT="$(mktemp)"
trap 'rm -f "$VERDICT"' EXIT

# Everything that has to reason about settings.json, in one program called
# twice: once to say what will happen, once to do it. Twice rather than once
# because the answer must not be carried across the confirmation prompt —
# the file can change while it waits — and one program rather than two so
# that the sentence shown to the user and the decision to delete come from
# the same lines. It writes its verdict to $VERDICT for the shell to read.
#
#   inspect  say what is there, decide nothing
#   apply    classify again and act on that, not on what inspect saw
#
settings_tool() {
    python3 - "$1" "$SETTINGS" "$EXPORTER" "$VERDICT" <<'PY'
import json, os, re, sys, tempfile
from datetime import datetime

mode, settings_arg, exporter, verdict_path = sys.argv[1:5]
path = os.path.realpath(settings_arg)
is_link = os.path.islink(settings_arg)


def spellings(exporter):
    """The ways one file path can be written in this file.

    The installer writes an absolute path, but the status line documentation
    spells its own example `~/.claude/statusline.sh`, so a hand-written entry
    is as likely to use the tilde. All of these name the same file, and a
    comparison that misses that either leaves our own key behind or — worse —
    deletes the exporter out from under a status line it does not recognise.
    """
    forms = [exporter]
    home = os.path.expanduser("~").rstrip("/")
    if home and exporter.startswith(home + "/"):
        rest = exporter[len(home):]
        forms += ["~" + rest, "$HOME" + rest, "${HOME}" + rest]
    return forms


FORMS = spellings(exporter)


def classify():
    """(state, what the status line runs, other places the exporter is named)

    States: no-file, invalid, absent, ours, foreign, unrecognised. Only `ours`
    may be deleted, and `ours` means `statusLine.command` is exactly the path
    of the exporter this installation wrote, in one of its spellings — not a
    command that contains that path, and not a file that mentions it.
    """
    if not os.path.exists(path):
        return "no-file", None, []
    with open(path, encoding="utf-8") as f:
        text = f.read()
    try:
        data = json.loads(text)
    except ValueError as exc:
        return "invalid", str(exc), []
    if not isinstance(data, dict):
        return "invalid", "the top level is not an object", []

    # The documented shape is an object with a string `command`
    # (claude-code/statusline.md). Anything else is not something this can
    # read, and what it cannot read it will not call ours.
    line = data.get("statusLine")
    if line is None:
        state = "absent"
    elif isinstance(line, dict) and isinstance(line.get("command"), str):
        state = "ours" if line["command"].strip() in FORMS else "foreign"
    else:
        state = "unrecognised"

    shown = None
    if state == "foreign":
        shown = line["command"]
    elif state == "unrecognised":
        shown = json.dumps(line, ensure_ascii=False)

    # Who else names the exporter. When the status line is ours it is about to
    # go, so it does not count as a reference to itself; in every other state
    # it does, and that is the wrapper-chaining case.
    references = []

    def walk(node, where):
        if isinstance(node, dict):
            for key, value in node.items():
                walk(value, f"{where}.{key}" if where else key)
        elif isinstance(node, list):
            for i, value in enumerate(node):
                walk(value, f"{where}[{i}]")
        elif isinstance(node, str) and any(form in node for form in FORMS):
            references.append(where)

    for key, value in data.items():
        if key == "statusLine" and state == "ours":
            continue
        walk(value, key)
    return state, shown, references


state, shown, references = classify()
keeps_exporter = bool(references) or state == "invalid"

with open(verdict_path, "w") as f:
    f.write(f"STATE={state}\n")
    f.write(f"REMOVE_EXPORTER={'no' if keeps_exporter else 'yes'}\n")

if state == "invalid":
    print("    settings.json is not valid JSON, so nothing in it can be")
    print("    identified as ours:")
    print(f"      {shown}")
    print("    Nothing there will be touched, and neither will the exporter —")
    print("    a status line this cannot read may well be calling it.")
    sys.exit(1)

if mode == "inspect":
    if is_link:
        # Said once, while describing the plan. Saying it again while acting
        # would be two sentences about one link.
        print("    settings.json is a symlink; the target is what is read and")
        print(f"    written: {path}")
    if state == "no-file":
        print("    there is no settings.json — nothing there to undo")
    elif state == "absent":
        print("    settings.json has no statusLine — left alone")
    elif state == "ours":
        print("    the statusLine key is ours and is removed (other keys untouched)")
    elif state == "foreign":
        print("    the statusLine runs something else and stays:")
        print(f"      {shown}")
    else:
        print("    the statusLine is not in a shape this can read, so it cannot be")
        print("    called ours. It stays:")
        print(f"      {shown}")
    for where in references:
        print(f"    settings.json still names the exporter at «{where}» —")
        print("    the exporter file stays, or that would point at nothing")
    sys.exit(0)

# --- apply ---------------------------------------------------------------

if state != "ours":
    # Reached only if the file changed between the plan and the prompt.
    print(f"!! The statusLine is no longer ours ({state}) — leaving it alone.")
    print("   settings.json changed while this was waiting for an answer.")
    sys.exit(0)

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
backup = os.path.join(os.path.dirname(settings_arg), f"settings.json.bak-{stamp}")
with open(path, "rb") as f:
    original_bytes = f.read()
# Opened 0600 rather than written and chmodded after: settings.json can hold
# environment variables and keys, and a backup that is briefly world-readable
# is a backup that was world-readable. The mode is read back by
# check-uninstall.sh rather than assumed from what the call is supposed to do.
fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "wb") as f:
    f.write(original_bytes)
print(f"==> Settings backup: {os.path.basename(backup)}")

text = original_bytes.decode("utf-8")
data = json.loads(text)
del data["statusLine"]

# Cut out only this key so the neighbours keep their indentation. If that
# fails, rebuild the file and say so.
pattern = re.compile(r'\n[ \t]*"statusLine"\s*:\s*\{[^{}]*\}\s*,?', re.S)
edited, count = pattern.subn("", text, count=1)
if count:
    edited = re.sub(r',(\s*\})', r'\1', edited)
try:
    surgical = bool(count) and json.loads(edited) == data
except ValueError:
    surgical = False

if not surgical:
    edited = json.dumps(data, indent=2, ensure_ascii=False) + "\n"

# Written to a neighbouring file and renamed over the original: a truncating
# write interrupted halfway leaves someone with no settings at all, and this
# is the fallback that runs when the app is already broken.
directory = os.path.dirname(path) or "."
mode_bits = os.stat(path).st_mode & 0o777
tmp_fd, tmp_path = tempfile.mkstemp(dir=directory, prefix=".settings.json.")
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        f.write(edited)
    os.chmod(tmp_path, mode_bits)
    os.replace(tmp_path, path)
except BaseException:
    os.unlink(tmp_path)
    raise

print("==> Removing the statusLine key")
if surgical:
    print("    key removed, the formatting around it is intact")
else:
    print("    surgical edit failed: the file was rebuilt, key order and indentation changed")
    print("    the original is in the backup next to it")
PY
}

read_verdict() {
    STATE=""
    REMOVE_EXPORTER="no"
    # shellcheck disable=SC1090
    while IFS='=' read -r key value; do
        case "$key" in
            STATE) STATE="$value" ;;
            REMOVE_EXPORTER) REMOVE_EXPORTER="$value" ;;
        esac
    done < "$VERDICT"
}

echo "==> What will happen"

# An unreadable settings.json stops everything before anything is removed. The
# alternative — carry on and delete the exporter — leaves a status line that
# may well be ours calling a file that is gone, at every prompt.
if ! settings_tool inspect; then
    echo
    echo "!! Nothing was removed. Fix the JSON and run this again, or remove"
    echo "   these by hand:"
    echo "     $EXPORTER"
    echo "     $INTEGRITY"
    echo "     the statusLine key in $SETTINGS"
    exit 1
fi
read_verdict

if [ ! -e "$EXPORTER" ]; then
    echo "    no exporter present"
elif [ "$REMOVE_EXPORTER" = "yes" ]; then
    echo "    deleting $EXPORTER"
else
    echo "    keeping $EXPORTER — see above"
fi

HISTORY_LINES=0
[ -f "$EXCHANGE/history.jsonl" ] && HISTORY_LINES=$(wc -l < "$EXCHANGE/history.jsonl" | tr -d ' ')
if [ "$PURGE" -eq 1 ]; then
    echo "    deleting the history ($HISTORY_LINES points) — the estimate restarts"
    echo "    deleting $APP"
else
    echo "    the history is kept ($HISTORY_LINES points); use --purge to delete it"
    echo "    $APP stays; remove it by hand or with --purge"
fi
echo

if [ "$DRY" -eq 0 ]; then
    printf "Continue? [y/N] "
    read -r answer
    case "$answer" in y|Y|yes|Yes) ;; *) echo "cancelled"; exit 0 ;; esac
fi

if [ "$STATE" = "ours" ]; then
    # The prefix is not decoration. A dry run that announces "Settings backup:
    # settings.json.bak-…" in the same words as a real one is telling the user
    # a file exists that does not, and the whole point of --dry-run is to be
    # believed.
    if [ "$DRY" -eq 1 ]; then
        echo "==> [dry run] A backup would be written as settings.json.bak-YYYYMMDD-HHMMSS"
        echo "==> [dry run] The statusLine key would be removed"
    else
        settings_tool apply
        read_verdict
    fi
fi

if [ "$REMOVE_EXPORTER" = "yes" ]; then
    step "Removing the exporter"
    run rm -f "$EXPORTER" "$INTEGRITY"
else
    echo "==> Keeping the exporter: settings.json still refers to it"
    echo "    $EXPORTER"
fi

if [ "$PURGE" -eq 1 ]; then
    step "Removing the history and the container"
    run rm -rf "$CONTAINER"
    step "Removing the app"
    run rm -rf "$APP"
    step "Restarting the widget daemon"
    [ "$DRY" -eq 0 ] && killall chronod 2>/dev/null || true
fi

echo
echo "==> Done"
if [ "$PURGE" -eq 0 ]; then
    echo "    Left to remove by hand, if you want to:"
    echo "      $APP"
    echo "      $CONTAINER"
    echo "    And drag the widget off your desktop."
fi
