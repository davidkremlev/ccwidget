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

echo "==> What will happen"

# --- statusLine ---
if [ -f "$SETTINGS" ] && grep -q "ccwidget-export.py" "$SETTINGS" 2>/dev/null; then
    echo "    the statusLine key is removed from settings.json (others untouched)"
    REMOVE_KEY=1
else
    echo "    statusLine does not point at us — settings.json left alone"
    REMOVE_KEY=0
fi

[ -f "$EXPORTER" ] && echo "    deleting $EXPORTER" || echo "    no exporter present"

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

# --- remove the key while preserving the formatting ---
if [ "$REMOVE_KEY" -eq 1 ]; then
    STAMP=$(date +%Y%m%d-%H%M%S)
    BACKUP="$CLAUDE_DIR/settings.json.bak-$STAMP"
    # The prefix is not decoration. A dry run that announces "Settings backup:
    # settings.json.bak-…" in the same words as a real one is telling the user
    # a file exists that does not, and the whole point of --dry-run is to be
    # believed.
    if [ "$DRY" -eq 1 ]; then
        echo "==> [dry run] Settings backup would be: $(basename "$BACKUP")"
    else
        echo "==> Settings backup: $(basename "$BACKUP")"
        cp "$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$SETTINGS")" "$BACKUP"
        chmod 600 "$BACKUP"
    fi

    if [ "$DRY" -eq 1 ]; then
        echo "==> [dry run] The statusLine key would be removed"
    else
        echo "==> Removing the statusLine key"
        python3 - "$SETTINGS" <<'PY'
import json, os, sys

path = os.path.realpath(sys.argv[1])
with open(path) as f:
    text = f.read()

data = json.loads(text)
if "statusLine" not in data:
    sys.exit(0)
del data["statusLine"]

# Try to cut out only this key so the neighbours keep their indentation.
# If that fails, rebuild the file and say so.
import re
pattern = re.compile(r'\n[ \t]*"statusLine"\s*:\s*\{[^{}]*\}\s*,?', re.S)
edited, count = pattern.subn("", text, count=1)
if count:
    edited = re.sub(r',(\s*\})', r'\1', edited)
try:
    ok = count and json.loads(edited) == data
except ValueError:
    ok = False

if ok:
    with open(path, "w") as f:
        f.write(edited)
    print("    key removed, the formatting around it is intact")
else:
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("    surgical edit failed: the file was rebuilt, key order and indentation changed")
    print("    the original is in the backup next to it")
PY
    fi
fi

echo "==> Removing the exporter"
run rm -f "$EXPORTER" "$INTEGRITY"

if [ "$PURGE" -eq 1 ]; then
    echo "==> Removing the history and the container"
    run rm -rf "$CONTAINER"
    echo "==> Removing the app"
    run rm -rf "$APP"
    echo "==> Restarting the widget daemon"
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
