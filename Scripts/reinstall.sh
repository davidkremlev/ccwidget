#!/bin/bash
#
# Builds and reinstalls CCWidget.app for development.
#
# The last step — killall chronod — is mandatory. Without it the widget daemon
# keeps running the previous build of the extension and your changes look as
# though they never applied. See SPEC.md, section 5.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-Release}"
DERIVED="$ROOT/.build/dd"
APP="/Applications/CCWidget.app"

# The Xcode project is generated from project.yml and is not in the repository,
# so regenerate it every time rather than only when it is missing: a file added
# to the tree since the last run would otherwise be silently left out of the
# build, and the symptom — code that does not seem to apply — looks exactly
# like the chronod problem below.
echo "==> Generating the Xcode project"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "!! xcodegen is not installed: brew install xcodegen" >&2
    exit 1
fi
(cd "$ROOT" && xcodegen generate --quiet)

echo "==> Building ($CONFIGURATION)"
xcodebuild \
    -project "$ROOT/CCWidget.xcodeproj" \
    -scheme CCWidget \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" \
    build \
    | grep -E "error:|warning:|BUILD" || true

BUILT="$DERIVED/Build/Products/$CONFIGURATION/CCWidget.app"
if [ ! -d "$BUILT" ]; then
    echo "!! The build produced no bundle: $BUILT" >&2
    exit 1
fi

echo "==> Stopping running copies"
pkill -f "$APP" 2>/dev/null || true
pkill -f CCWidgetExtension 2>/dev/null || true
sleep 2

echo "==> Installing into $APP"
rm -rf "$APP"
cp -R "$BUILT" "$APP"
codesign -v --deep --strict "$APP"
sleep 1

echo "==> Launching (this registers the extension with the system)"
open "$APP"
sleep 3

# The widget daemon keeps the extension loaded and survives the bundle being
# replaced. Without a restart it draws the old code over the new files, which
# looks exactly like changes that did not apply.
echo "==> Restarting the widget daemon"
killall chronod 2>/dev/null || true

# The extension crashed on every render for five hours on 7 August while all
# 221 checks were green: they run in a test process, and there is no WidgetKit
# in one. A crash does not blank the tile — the system keeps showing the last
# frame that rendered — so from the desktop it looks like stale data. Nothing
# short of watching a real machine catches that, so the install watches.
if [ "${1:-}" != "--no-health" ] && [ "${2:-}" != "--no-health" ]; then
    echo "==> Waiting 45s for the system to render the widget, then checking"
    sleep 45
    if ! "$ROOT/Scripts/check-widget-health.sh"; then
        echo
        echo "!! Installed, but the extension is not healthy. The tile will keep"
        echo "   showing its last good frame, which looks like stale data."
        exit 1
    fi

    # Surviving is not the same as drawing. Later the same day the extension
    # stopped crashing and the medium tile went black instead: every timeline
    # built, nothing was logged, and the check above said "healthy" about a
    # tile with nothing on it. So the install also looks at the tile.
    echo "==> Checking that the tile actually drew something"
    swift "$ROOT/Scripts/tile-probe.swift"
    case $? in
        0) ;;
        1) echo
           echo "!! Installed, and the tile is blank. Nothing crashed — this is"
           echo "   the quiet failure, not the loud one."
           exit 1 ;;
        *) echo
           echo "   (Installed. The tile could not be judged — see above.)" ;;
    esac
fi

echo "==> Done. Logs:"
echo "    log stream --predicate 'subsystem == \"dev.illvminat.ccwidget\"' --level info"
