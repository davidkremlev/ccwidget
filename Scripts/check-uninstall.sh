#!/bin/bash
#
# Does the uninstaller remove only what belongs to us?
#
# `uninstall.sh` edits a file it does not own. On 7 August 2026 a security
# review found it deciding "this statusLine is ours" by grepping the whole of
# settings.json for the substring `ccwidget-export.py` — so a user whose own
# status line merely mentioned the exporter, or who referred to it from a hook,
# lost their configuration. The project charter forbids exactly that, and
# nothing checked it, because nothing checked this script at all.
#
# This is that check. It runs the real uninstaller against a stand-in home, one
# throwaway home per case, and looks at what is on disk afterwards.
#
#   ./Scripts/check-uninstall.sh                    # check Scripts/uninstall.sh
#   ./Scripts/check-uninstall.sh /path/to/other.sh  # check some other copy
#
# The script under test is an argument rather than a constant so that a broken
# copy can be run through the same cases: a check nobody has seen fail is a
# check nobody has tested.
#
# --purge is never passed. It deletes /Applications/CCWidget.app, which is not
# under the stand-in home and would be a real removal on the real machine.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNDER_TEST="${1:-$ROOT/Scripts/uninstall.sh}"

if [ ! -f "$UNDER_TEST" ]; then
    echo "!! No such uninstaller: $UNDER_TEST" >&2
    exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0
CASE=""
STAGE=""
OUT=""
STATUS=0

# --- the stand-in home ---------------------------------------------------

# Each case gets its own home so that one case cannot leave the next one
# something to trip over.
stage() {
    CASE="$1"
    STAGE="$WORK/$(echo "$1" | tr ' /' '--')"
    rm -rf "$STAGE"
    mkdir -p "$STAGE/.claude"
    printf 'print("exporter")\n' > "$STAGE/.claude/ccwidget-export.py"
    chmod +x "$STAGE/.claude/ccwidget-export.py"
    printf 'deadbeef\n' > "$STAGE/.claude/.ccwidget-export.sha256"
    echo "==> $CASE"
}

settings() {
    cat > "$STAGE/.claude/settings.json"
}

exporter_path() { echo "$STAGE/.claude/ccwidget-export.py"; }

# Runs the uninstaller against the current stage, answering the prompt with
# yes. HOME is the only thing that points it at the stand-in home, and that is
# the whole reason this is checkable.
run_uninstall() {
    OUT="$(printf 'y\n' | HOME="$STAGE" bash "$UNDER_TEST" "$@" 2>&1)"
    STATUS=$?
}

# With no answer on stdin at all: --yes must not wait for one. Without --yes the
# same call must refuse rather than proceed, because a removal that happens
# because nobody said no is the same defect as one that happens silently.
run_uninstall_unattended() {
    OUT="$(HOME="$STAGE" bash "$UNDER_TEST" "$@" < /dev/null 2>&1)"
    STATUS=$?
}

# --- assertions ----------------------------------------------------------

fail() {
    failed=$((failed + 1))
    echo "    FAIL  $1"
    if [ -n "${2:-}" ]; then echo "          $2"; fi
}

pass() {
    passed=$((passed + 1))
    echo "    ok    $1"
}

expect_settings_unchanged() {
    local before="$1"
    local now
    now="$(cat "$STAGE/.claude/settings.json" 2>/dev/null)"
    if [ "$now" = "$before" ]; then
        pass "settings.json is untouched, byte for byte"
    else
        fail "settings.json was edited and should not have been" "$(diff <(echo "$before") <(echo "$now") | head -12)"
    fi
}

expect_no_status_line() {
    if python3 -c "import json,sys; sys.exit(0 if 'statusLine' not in json.load(open(sys.argv[1])) else 1)" \
            "$STAGE/.claude/settings.json"; then
        pass "the statusLine key is gone"
    else
        fail "the statusLine key is still there"
    fi
}

expect_key_kept() {
    if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d else 1)" \
            "$STAGE/.claude/settings.json" "$1"; then
        pass "the neighbouring key \"$1\" survived"
    else
        fail "the neighbouring key \"$1\" was lost"
    fi
}

expect_exporter_gone() {
    if [ -e "$(exporter_path)" ]; then
        fail "the exporter is still there and should have been removed"
    else
        pass "the exporter was removed"
    fi
}

expect_exporter_kept() {
    if [ -e "$(exporter_path)" ]; then
        pass "the exporter is still there"
    else
        fail "the exporter was deleted while something else still refers to it" \
             "whatever refers to it now points at a file that is gone"
    fi
}

expect_says() {
    if printf '%s' "$OUT" | grep -qF -- "$1"; then
        pass "it says so out loud: «$1»"
    else
        fail "it never mentions «$1»" "$(printf '%s' "$OUT" | tail -6)"
    fi
}

expect_silent_about() {
    if printf '%s' "$OUT" | grep -qF -- "$1"; then
        fail "it claims «$1», which did not happen" "$(printf '%s' "$OUT" | tail -6)"
    else
        pass "it does not claim «$1»"
    fi
}

expect_status() {
    if [ "$STATUS" = "$1" ]; then
        pass "exit status $1"
    else
        fail "exit status $STATUS, expected $1"
    fi
}

expect_status_not() {
    if [ "$STATUS" != "$1" ]; then
        pass "exit status is $STATUS, and not $1"
    else
        fail "exit status $STATUS, and it should not be"
    fi
}

expect_backup_0600() {
    local backup
    backup="$(ls "$STAGE/.claude"/settings.json.bak-* 2>/dev/null | head -1)"
    if [ -z "$backup" ]; then
        fail "no backup was made before editing someone's settings"
        return
    fi
    local mode
    mode="$(stat -f %Lp "$backup")"
    if [ "$mode" = "600" ]; then
        pass "the backup is 0600"
    else
        fail "the backup is $mode; settings.json can hold keys and environment"
    fi
}

expect_no_backup() {
    if ls "$STAGE/.claude"/settings.json.bak-* >/dev/null 2>&1; then
        fail "a backup was made although nothing was edited"
    else
        pass "no backup was made, because nothing was edited"
    fi
}

OURS_CMD=""

# --- the cases -----------------------------------------------------------
#
# One per state the uninstaller can find the status line in. A state nobody
# expects is wrong for ever: there is nothing to notice it with.

# 1. Ours. The one case where the key may be deleted.
stage "ours"
OURS_CMD="$(exporter_path)"
settings <<EOF
{
  "model": "opus",
  "statusLine": {
    "type": "command",
    "command": "$OURS_CMD",
    "padding": 0
  },
  "theme": "dark"
}
EOF
run_uninstall
expect_status 0
expect_no_status_line
expect_key_kept model
expect_key_kept theme
expect_exporter_gone
expect_backup_0600

# 2. Somebody else's status line, no mention of us anywhere.
stage "foreign"
settings <<'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "/usr/local/bin/my-own-statusline"
  }
}
EOF
before="$(cat "$STAGE/.claude/settings.json")"
run_uninstall
expect_status 0
expect_settings_unchanged "$before"
expect_says "/usr/local/bin/my-own-statusline"
expect_no_backup
expect_exporter_gone

# 3. The audit's case: a wrapper of their own that chains our exporter.
#    Deleting the key takes away their status line; deleting the exporter
#    leaves their wrapper calling a file that is gone.
stage "foreign chained"
settings <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "/bin/sh -c '$(exporter_path) | tee -a ~/.claude/statusline.log'"
  }
}
EOF
before="$(cat "$STAGE/.claude/settings.json")"
run_uninstall
expect_status 0
expect_settings_unchanged "$before"
expect_exporter_kept
expect_says "/bin/sh -c"

# 4. No status line of ours, but a hook refers to the exporter.
stage "referred to by a hook"
settings <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$(exporter_path)" } ] }
    ]
  }
}
EOF
before="$(cat "$STAGE/.claude/settings.json")"
run_uninstall
expect_status 0
expect_settings_unchanged "$before"
expect_exporter_kept
expect_no_backup

# 5. Nothing of ours in the file at all.
stage "absent"
settings <<'EOF'
{ "model": "opus" }
EOF
before="$(cat "$STAGE/.claude/settings.json")"
run_uninstall
expect_status 0
expect_settings_unchanged "$before"
expect_exporter_gone
expect_no_backup

# 6. A status line in a shape we do not recognise, mentioning our path. Not
#    ours by the only test that means anything — an exact match on `command`.
stage "unrecognised shape"
settings <<EOF
{
  "statusLine": {
    "type": "command",
    "command": [ "python3", "$(exporter_path)" ]
  }
}
EOF
before="$(cat "$STAGE/.claude/settings.json")"
run_uninstall
expect_settings_unchanged "$before"
expect_exporter_kept

# 7. The file is not JSON. Nothing can be decided about it, so nothing is
#    touched — including the exporter, which a status line we cannot read
#    might well be calling.
stage "invalid json"
settings <<EOF
{ "statusLine": { "command": "$(exporter_path)",, }
EOF
before="$(cat "$STAGE/.claude/settings.json")"
run_uninstall
expect_status_not 0
expect_settings_unchanged "$before"
expect_exporter_kept
expect_no_backup
expect_silent_about "Traceback"
expect_silent_about "==> Done"

# 8. No settings.json at all — the app never got as far as writing one.
stage "no settings file"
rm -f "$STAGE/.claude/settings.json"
run_uninstall
expect_status 0
expect_exporter_gone
if [ -e "$STAGE/.claude/settings.json" ]; then
    fail "a settings.json was created out of nothing"
else
    pass "no settings.json was conjured up"
fi

# 9. A dry run changes nothing, on the one case where a real run would.
stage "dry run over ours"
settings <<EOF
{
  "statusLine": { "type": "command", "command": "$(exporter_path)" }
}
EOF
before="$(cat "$STAGE/.claude/settings.json")"
run_uninstall --dry-run
expect_status 0
expect_settings_unchanged "$before"
expect_exporter_kept
expect_no_backup

# 10. The file changes while the prompt is waiting for an answer. The plan
#     said "ours"; by the time the answer arrives it is someone else's. The
#     decision has to be made again at the moment of acting, or a race here
#     deletes a key that was ours only in the past tense.
stage "changed while the prompt waited"
settings <<EOF
{ "statusLine": { "type": "command", "command": "$(exporter_path)" } }
EOF
FIFO="$STAGE/answer"
mkfifo "$FIFO"
LOG="$STAGE/output"
(
    # The fifo is opened first and held: the uninstaller blocks on opening
    # it for reading, so a writer that waits for the prompt before opening
    # would be waiting for a script that has not started.
    exec 3>"$FIFO"
    # Wait for the prompt, then swap the file under it and answer yes.
    for _ in $(seq 1 200); do
        grep -q "Continue?" "$LOG" 2>/dev/null && break
        sleep 0.05
    done
    cat > "$STAGE/.claude/settings.json" <<'INNER'
{ "statusLine": { "type": "command", "command": "/usr/local/bin/somebody-else" } }
INNER
    printf 'y\n' >&3
    exec 3>&-
) &
HOME="$STAGE" bash "$UNDER_TEST" < "$FIFO" > "$LOG" 2>&1
STATUS=$?
wait
OUT="$(cat "$LOG")"
if grep -q "somebody-else" "$STAGE/.claude/settings.json"; then
    pass "the key that appeared during the prompt was not deleted"
else
    fail "a key that was not ours at the moment of acting was deleted" "$(cat "$STAGE/.claude/settings.json")"
fi
expect_says "no longer ours"

# 11. settings.json is a symlink into a dotfiles repository. The edit has to
#     go through to the target: replacing the link with a regular file breaks
#     the connection to the repository silently, which is the same trap the
#     installer documents on the writing side.
stage "settings behind a symlink"
mkdir -p "$STAGE/dotfiles"
cat > "$STAGE/dotfiles/claude-settings.json" <<EOF
{
  "model": "opus",
  "statusLine": { "type": "command", "command": "$(exporter_path)" }
}
EOF
rm -f "$STAGE/.claude/settings.json"
ln -s "$STAGE/dotfiles/claude-settings.json" "$STAGE/.claude/settings.json"
run_uninstall
expect_status 0
expect_no_status_line
expect_key_kept model
expect_says "symlink"
if [ -L "$STAGE/.claude/settings.json" ]; then
    pass "settings.json is still a symlink"
else
    fail "the symlink was replaced by a regular file; the dotfiles link is broken"
fi
if ls "$STAGE/.claude"/settings.json.bak-* >/dev/null 2>&1; then
    pass "the backup sits next to the link, where the uninstaller says it is"
else
    fail "no backup in ~/.claude"
fi

# 12. The same key written the way the status line documentation writes its
#     own example — with a tilde. It names the file the installer wrote, so it
#     is ours however it is spelled.
stage "ours through a tilde"
settings <<'EOF'
{ "statusLine": { "type": "command", "command": "~/.claude/ccwidget-export.py" } }
EOF
run_uninstall
expect_status 0
expect_no_status_line
expect_exporter_gone

# 13. And a wrapper of someone else's that chains the $HOME spelling. The old
#     substring test would have found the exporter's name here too; what makes
#     this different is that the whole command is not the exporter.
stage "foreign chaining the HOME spelling"
settings <<'EOF'
{ "statusLine": { "type": "command", "command": "$HOME/.claude/ccwidget-export.py | sed s/x/y/" } }
EOF
before="$(cat "$STAGE/.claude/settings.json")"
run_uninstall
expect_status 0
expect_settings_unchanged "$before"
expect_exporter_kept

# 14. Ours, and a hook of theirs calls the exporter too. The key goes, the
#     file stays: the two decisions are separate, and only the second one is
#     about who else needs it.
stage "ours with a hook that also calls it"
settings <<EOF
{
  "statusLine": { "type": "command", "command": "$(exporter_path)" },
  "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "$(exporter_path) --log" } ] } ] }
}
EOF
run_uninstall
expect_status 0
expect_no_status_line
expect_key_kept hooks
expect_exporter_kept
expect_says "hooks.Stop"

# 15. Ours, with somebody's own status line chained behind it. Removal has to
#     put theirs back rather than delete the key — the app does, and the two
#     paths disagreeing is what the last batch was spent on.
stage "ours with a chained status line"
settings <<EOF
{
  "theme": "dark",
  "statusLine": { "type": "command", "command": "$(exporter_path)", "padding": 4 }
}
EOF
cat > "$STAGE/.claude/ccwidget-export.py" <<'INNER'
#!/usr/bin/env python3
CHAINED = "/usr/local/bin/theirs"
print("exporter")
INNER
run_uninstall
expect_status 0
expect_says "/usr/local/bin/theirs"
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('statusLine',{}).get('command') == '/usr/local/bin/theirs' else 1)" "$STAGE/.claude/settings.json"; then
    pass "their command is what the status line runs again"
else
    fail "the status line was not put back" "$(cat "$STAGE/.claude/settings.json")"
fi
expect_key_kept theme
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('statusLine',{}).get('padding') == 4 else 1)" "$STAGE/.claude/settings.json"; then
    pass "and the rest of their object with it"
else
    fail "padding was lost while restoring"
fi
expect_exporter_gone

# 16. Ours with nothing chained: the key goes, as it always did. The two cases
#     must not be confused in either direction.
stage "ours with nothing chained"
settings <<EOF
{ "theme": "dark", "statusLine": { "type": "command", "command": "$(exporter_path)" } }
EOF
cat > "$STAGE/.claude/ccwidget-export.py" <<'INNER'
#!/usr/bin/env python3
CHAINED = None
INNER
run_uninstall
expect_status 0
expect_no_status_line
expect_key_kept theme
expect_exporter_gone

# 17. `--yes`, which is how `brew uninstall` invokes this: no terminal, no
#     answer to give. It has to go ahead, say that it is going ahead, and the
#     same call without the flag has to do nothing.
stage "unattended with --yes"
settings <<EOF
{ "theme": "dark", "statusLine": { "type": "command", "command": "$(exporter_path)" } }
EOF
cat > "$STAGE/.claude/ccwidget-export.py" <<'INNER'
#!/usr/bin/env python3
CHAINED = None
INNER
run_uninstall_unattended --yes
expect_status 0
expect_no_status_line
expect_exporter_gone
expect_says "going ahead without asking"

stage "unattended without --yes"
settings <<EOF
{ "theme": "dark", "statusLine": { "type": "command", "command": "$(exporter_path)" } }
EOF
before="$(cat "$STAGE/.claude/settings.json")"
run_uninstall_unattended
expect_settings_unchanged "$before"
if [ -e "$(exporter_path)" ]; then
    pass "nothing was removed without an answer"
else
    fail "it removed things with nobody there to agree"
fi

# --- verdict -------------------------------------------------------------

echo
if [ "$failed" -eq 0 ]; then
    echo "==> $passed checks passed against $(basename "$UNDER_TEST")"
    exit 0
fi
echo "!! $failed of $((passed + failed)) checks failed against $UNDER_TEST"
exit 1
