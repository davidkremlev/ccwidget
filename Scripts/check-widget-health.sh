#!/bin/bash
#
# Did the widget extension build a timeline and survive doing it?
#
# Every check this project has runs in a test process where there is no
# WidgetKit, no timeline and no system. On 7 August 2026 two hundred and
# twenty-one of them were green while the extension was crashing on every
# render — SwiftUI's layout tripped an assertion inside WidgetKit's
# `_ArchivedViewHost`, which no ImageRenderer in a console tool reproduces.
# The tile went on showing the last frame that had rendered successfully, so
# both the data and the layout on screen were hours old and looked merely
# stale rather than broken.
#
# This is the check that would have caught it. It runs on a real machine
# against the installed bundle, so it belongs beside reinstall.sh rather than
# in CI.
#
#   ./Scripts/check-widget-health.sh            # look back over the last 10 min
#   ./Scripts/check-widget-health.sh 120        # ... over the last 120 min
#
# Exit codes: 0 healthy, 1 crashed, 2 no evidence either way.
set -uo pipefail

# Where the crash reports are read from. Overridable because the branch that
# matters most here — "the extension crashed, here is the stack" — cannot be
# exercised against the real directory: it reports a crash only when there has
# been one, so the code that names the faulting frames would be run for the
# first time on the day it is needed. Point this at a directory holding a
# report and the branch runs on demand.
REPORTS="${CCWIDGET_REPORTS_DIR:-$HOME/Library/Logs/DiagnosticReports}"
SUBSYSTEM="dev.illvminat.ccwidget"
BINARY="/Applications/CCWidget.app/Contents/PlugIns/CCWidgetExtension.appex/Contents/MacOS/CCWidgetExtension"

# The question is not "did anything crash lately" but "has *this build*
# crashed". Reports older than the installed binary belong to whatever was
# installed before it, and counting them makes a fixed build look broken —
# which happened on the first run of this script.
# macOS rewrites the mtime of old .ips files — observed: a report born at
# 16:10 carried an mtime of 16:39 — so `find -newer` calls yesterday's crash
# today's. The creation time is in the filename, and that is what is used.
#
#   CCWidgetExtension-2026-08-07-163815.ips  ->  2026-08-07 16:38:15
since_epoch() {
    python3 - "$1" "$2" <<'PYEOF'
import re, sys, datetime, pathlib, os
cutoff = float(sys.argv[2])
out = []
for path in pathlib.Path(sys.argv[1]).glob("CCWidgetExtension-*.ips"):
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})", path.name)
    if not m:
        continue
    born = datetime.datetime(*map(int, m.groups())).timestamp()
    if born >= cutoff:
        out.append(path.as_posix())
print("\n".join(sorted(out)))
PYEOF
}

if [ -n "${1:-}" ]; then
    MINUTES="$1"
    echo "==> Looking back $MINUTES minutes"
    cutoff=$(( $(date +%s) - MINUTES * 60 ))
else
    if [ ! -x "$BINARY" ]; then
        echo "!! No installed extension at $BINARY"; exit 2
    fi
    cutoff=$(stat -f %m "$BINARY")
    MINUTES=$(( ( $(date +%s) - cutoff ) / 60 + 1 ))
    echo "==> Since this build was installed — $(stat -f "%Sm" "$BINARY"), $MINUTES minute(s) ago"
fi
crashes=$(since_epoch "$REPORTS" "$cutoff")
crash_count=$(printf '%s' "$crashes" | grep -c . || true)

# 2. Did the provider get as far as building a timeline? Its log is at .info,
#    which `log show` hides unless asked — a trap that cost half a day once.
built=$(/usr/bin/log show --info --last "${MINUTES}m" \
        --predicate "subsystem == \"$SUBSYSTEM\" AND category == \"widget\"" \
        --style compact 2>/dev/null | grep -c "timeline built" || true)

echo "    timelines built: $built"
echo "    crash reports:   $crash_count"

if [ "$crash_count" -gt 0 ]; then
    echo
    echo "!! The extension crashed. Most recent reports:"
    printf '%s\n' "$crashes" | tail -3 | sed 's|.*/|     |'
    newest=$(printf '%s\n' "$crashes" | tail -1)
    echo
    echo "   Faulting frames:"
    python3 - "$newest" <<'PY' || true
import json, sys
try:
    d = json.loads(open(sys.argv[1]).read().split("\n", 1)[1])
except Exception as exc:
    print("     (could not parse:", exc, ")"); raise SystemExit
images = d.get("usedImages", [])
def name(i):
    try: return images[i].get("name") or "?"
    except Exception: return "?"
th = d["threads"][d.get("faultingThread", 0)]
for frame in th["frames"][:6]:
    print(f"     {name(frame.get('imageIndex', -1)):<22} {(frame.get('symbol') or '')[:70]}")
PY
    echo
    echo "   A crashing extension does not blank the tile: the system keeps"
    echo "   showing the last frame that rendered, so stale data and stale"
    echo "   layout are what this looks like from the desktop."
    exit 1
fi

if [ "$built" -eq 0 ]; then
    echo
    echo "?? No timeline was built in that window, and nothing crashed either."
    echo "   Nothing to conclude. Add the widget to the desktop, or reload it:"
    echo "     killall chronod"
    exit 2
fi

echo
echo "==> Healthy: the provider built $built timeline(s) and the extension did not crash."
