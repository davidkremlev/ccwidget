#!/bin/bash
#
# Builds a copy of the app that somebody else's Mac will open.
#
# Everything the project has shipped so far is ad-hoc signed, which is fine on
# the machine that compiled it and refused everywhere else: Gatekeeper says
# "Apple could not verify this app is free of malware", offers Move to Trash,
# and does not offer Open. That single fact is what has kept the audience down
# to people who own Xcode.
#
# This does the four things that change it — sign with a Developer ID, harden
# the runtime, notarize, staple — and checks each one rather than assuming it
# worked. The order matters: inside out, because signing a bundle seals what is
# already inside it, and a re-signed extension inside a signed app invalidates
# the app's own seal.
#
#   ./Scripts/release.sh                 # the whole way, including notarizing
#   ./Scripts/release.sh --no-notarize   # stop after signing; no credentials needed
#   ./Scripts/release.sh --allow-dirty   # build from an uncommitted tree
#
# Notarizing needs credentials this script will not ask you for and does not
# want to see. Create them once, in your own shell:
#
#   xcrun notarytool store-credentials ccwidget-notary \
#       --apple-id <your Apple ID> --team-id C25S68RZ4N
#
# It asks for an app-specific password — appleid.apple.com, Sign-In and
# Security, App-Specific Passwords. Not your Apple ID password.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/.build/release-dd"
STAGE="$ROOT/.build/release"
NOTARY_PROFILE="ccwidget-notary"

NOTARIZE=1
ALLOW_DIRTY=0
for argument in "$@"; do
    case "$argument" in
        --no-notarize) NOTARIZE=0 ;;
        --allow-dirty) ALLOW_DIRTY=1 ;;
        *) echo "!! Unknown option: $argument" >&2
           echo "   Usage: release.sh [--no-notarize] [--allow-dirty]" >&2
           exit 2 ;;
    esac
done

# A release is a claim that a particular commit produced a particular binary.
# Building from a tree with uncommitted edits in it makes that claim false and
# nothing downstream can tell.
if [ "$ALLOW_DIRTY" -eq 0 ] && [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
    echo "!! The working tree has uncommitted changes, so the build could not be" >&2
    echo "   reproduced from any commit. Commit them, or pass --allow-dirty and" >&2
    echo "   know that the version number will name a commit this is not." >&2
    exit 1
fi

# --- who is signing -------------------------------------------------------

# Read from the keychain rather than written into the script: a team
# identifier in a public repository is not a secret, but a script that only
# works on one machine is worse than one that says what it could not find.
IDENTITY="$(security find-identity -v -p codesigning \
            | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
if [ -z "$IDENTITY" ]; then
    echo "!! No Developer ID Application certificate in the keychain." >&2
    echo "   Xcode › Settings › Accounts › Manage Certificates › + › Developer ID" >&2
    echo "   Application. A Developer Program membership is required for it." >&2
    exit 1
fi
TEAM_ID="$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2 }' "$ROOT/project.yml")"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"

echo "==> Releasing $VERSION ($COMMIT)"
echo "    signing as: $IDENTITY"
echo "    team:       $TEAM_ID"

# --- build ----------------------------------------------------------------

echo "==> Building Release"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "!! xcodegen is not installed: brew install xcodegen" >&2
    exit 1
fi
(cd "$ROOT" && xcodegen generate --quiet)
rm -rf "$STAGE"
mkdir -p "$STAGE"

# CODE_SIGN_IDENTITY is overridden here rather than in project.yml on purpose.
# The checked-in project stays ad-hoc so that anyone can clone and build
# without a Developer Program membership; the identity belongs to the act of
# releasing, not to the project.
xcodebuild \
    -project "$ROOT/CCWidget.xcodeproj" \
    -scheme CCWidget \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    ENABLE_CODE_COVERAGE=NO \
    CCWIDGET_COMMIT="$COMMIT" \
    build \
    | grep -E "error:|warning:|BUILD" || true

BUILT="$DERIVED/Build/Products/Release/CCWidget.app"
if [ ! -d "$BUILT" ]; then
    echo "!! The build produced no bundle: $BUILT" >&2
    exit 1
fi
cp -R "$BUILT" "$STAGE/CCWidget.app"
APP="$STAGE/CCWidget.app"
EXTENSION="$APP/Contents/PlugIns/CCWidgetExtension.appex"

# --- both architectures ---------------------------------------------------

# A release that runs only on Apple Silicon would be discovered by an Intel
# user, not by us. Checked rather than trusted to a default that has changed
# between Xcode versions before.
echo "==> Checking both architectures are in it"
for binary in "$APP/Contents/MacOS/CCWidget" "$EXTENSION/Contents/MacOS/CCWidgetExtension"; do
    archs="$(lipo -archs "$binary")"
    case "$archs" in
        *arm64*x86_64*|*x86_64*arm64*) echo "    $(basename "$binary"): $archs" ;;
        *) echo "!! $(basename "$binary") is $archs — not universal" >&2; exit 1 ;;
    esac
done

# --- take the build machine out of the binaries ---------------------------

# `strings` says these binaries are clean. They are not: the debug symbol table
# carries one entry per object file, and each one is an absolute path —
#
#     /Users/<name>/Documents/<folders>/ccwidget/.build/…/AgeClock.o
#
# — so the shipped app names the account it was built on and every folder above
# it. Fifty-seven such entries were in the first release. They are invisible to
# `strings` because they live in the symbol table rather than in the string
# section, which is exactly why "I grepped it and it looked clean" is not an
# answer to this question.
#
# Stripping debug symbols removes them. Nothing is lost that anyone needs: the
# symbols a crash report resolves against live in the .dSYM beside the build,
# and that is not what gets shipped. This runs before signing, because a
# binary modified after signing is a broken signature.
# `ENABLE_CODE_COVERAGE=NO` above is not a tidiness setting. It defaults to
# YES, and a Release build made with it carries LLVM's profiling machinery:
# 424 `__profc_` symbols in the first release, `__llvm_prf_*` sections, and
# inside each symbol the absolute path of the source file it counts —
# `__profc_/Users/<name>/Documents/<folders>/ccwidget/Shared/Diagnostics.swift`.
# So the shipped app named the account and the folder tree it was built in, and
# carried instrumentation nobody asked for into everybody's widget.

echo "==> Stripping the build machine out of the binaries"
strip -S "$APP/Contents/MacOS/CCWidget"
strip -S "$EXTENSION/Contents/MacOS/CCWidgetExtension"

for binary in "$APP/Contents/MacOS/CCWidget" "$EXTENSION/Contents/MacOS/CCWidgetExtension"; do
    leaks="$(nm -pa "$binary" 2>/dev/null | grep -cE " (OSO|SO) " || true)"
    profiling="$(nm "$binary" 2>/dev/null | grep -c "__profc_" || true)"
    # A raw byte search, not `strings`: the paths that mattered here were inside
    # symbol names, and `strings` reported eight hits where a byte search found
    # them in three different places. The question is "is this string in this
    # file", so the check asks exactly that.
    home="$(LC_ALL=C grep -ac "$(basename "$HOME")/Documents" "$binary" || true)"
    if [ "${leaks:-0}" -ne 0 ] || [ "${profiling:-0}" -ne 0 ] || [ "${home:-0}" -ne 0 ]; then
        echo "!! $(basename "$binary") still names the machine it was built on:" >&2
        echo "   $leaks debug path entries, $profiling profiling symbols, $home home-path hits." >&2
        nm -pa "$binary" 2>/dev/null | grep -E " (OSO|SO) |__profc_" | head -3 >&2
        exit 1
    fi
    echo "    $(basename "$binary"): no build paths, no profiling symbols, no home path"
done

# --- sign, inside out -----------------------------------------------------

echo "==> Signing"
codesign --force --sign "$IDENTITY" \
    --entitlements "$ROOT/Widget/CCWidgetExtension.entitlements" \
    --options runtime --timestamp \
    "$EXTENSION"
codesign --force --sign "$IDENTITY" \
    --options runtime --timestamp \
    "$APP"

echo "==> Checking the signature"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
# The flags are the part that is easy to lose and impossible to see: without
# `runtime` the notary service rejects the upload, with a message about the
# hardened runtime that reads like a certificate problem.
for bundle in "$APP" "$EXTENSION"; do
    flags="$(codesign -dvv "$bundle" 2>&1 | sed -n 's/^CodeDirectory .*flags=\([^ ]*\).*/\1/p')"
    case "$flags" in
        *runtime*) echo "    $(basename "$bundle"): hardened runtime on" ;;
        *) echo "!! $(basename "$bundle") is not hardened: flags=$flags" >&2; exit 1 ;;
    esac
done
codesign -dvv "$APP" 2>&1 | grep -E "^Authority|^TeamIdentifier|^Timestamp" | sed 's/^/    /'

# --- notarize the app, then package it -------------------------------------

# The app is notarized and stapled *before* it goes into the disk image, and
# that order is the whole point. Notarizing only the image staples a ticket to
# the image; the app a person drags out of it carries none, and its first
# launch then depends on Gatekeeper reaching Apple over the network. The first
# run of this script did exactly that and its own last check said so —
# "CCWidget.app does not have a ticket stapled to it" — which is why the check
# is there and why this is now two submissions rather than one.

notary_or_stop() {
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        return 0
    fi
    echo >&2
    echo "!! No notary credentials stored under the profile '$NOTARY_PROFILE'." >&2
    echo "   This script will not ask you for a password. Run this yourself:" >&2
    echo >&2
    echo "     xcrun notarytool store-credentials $NOTARY_PROFILE \\" >&2
    echo "         --apple-id <your Apple ID> --team-id $TEAM_ID" >&2
    echo >&2
    echo "   It wants an app-specific password: appleid.apple.com › Sign-In and" >&2
    echo "   Security › App-Specific Passwords. Then run this script again." >&2
    exit 1
}

# Submits one file and refuses to continue on anything but Accepted, printing
# what the service objected to rather than the word "Invalid".
notarize() {
    local file="$1" log="$STAGE/notary-$(basename "$1").log"
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait \
        | tee "$log" | grep -vE "Current status: In Progress" | sed 's/^/    /'
    if ! grep -q "status: Accepted" "$log"; then
        local id
        id="$(sed -n 's/.*id: \([0-9a-f-]*\).*/\1/p' "$log" | head -1)"
        echo >&2
        echo "!! $(basename "$file") was not accepted. What the service objected to:" >&2
        [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
        exit 1
    fi
}

DMG="$STAGE/CCWidget-$VERSION.dmg"

if [ "$NOTARIZE" -eq 0 ]; then
    ROOM="$STAGE/dmg"
    rm -rf "$ROOM"; mkdir -p "$ROOM"
    cp -R "$APP" "$ROOM/"
    ln -s /Applications "$ROOM/Applications"
    hdiutil create -quiet -volname "Usage Widget for Claude Code" \
        -srcfolder "$ROOM" -ov -format UDZO "$DMG"
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
    echo
    echo "==> Signed, not notarized (--no-notarize)"
    echo "    $DMG"
    echo
    echo "    Gatekeeper will still refuse this on another Mac. Signing says who"
    echo "    built it; notarizing is Apple saying they have looked at it, and"
    echo "    only the second one opens the app on a machine that did not build"
    echo "    it. Run without the flag once credentials exist."
    exit 0
fi

notary_or_stop

echo "==> Notarizing the app (a few minutes)"
ZIP="$STAGE/CCWidget.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"

echo "==> Stapling the ticket to the app"
xcrun stapler staple "$APP" | sed 's/^/    /'

echo "==> Building $(basename "$DMG") around the stapled app"
ROOM="$STAGE/dmg"
rm -rf "$ROOM"; mkdir -p "$ROOM"
cp -R "$APP" "$ROOM/"
ln -s /Applications "$ROOM/Applications"
hdiutil create -quiet -volname "Usage Widget for Claude Code" \
    -srcfolder "$ROOM" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "==> Notarizing the disk image (a few minutes)"
notarize "$DMG"

echo "==> Stapling the ticket to the disk image"
xcrun stapler staple "$DMG" | sed 's/^/    /'

# --- the only verdict that counts -----------------------------------------

# Not "did the commands succeed" but "would another Mac open this". The app is
# taken back out of the image, because that is the copy a person ends up with,
# and it is asked both questions: does Gatekeeper accept it, and does it carry
# its own ticket. The second is what fails when the app has not been stapled
# and only the image has — an app that works on a connected Mac and not on one
# that is offline.
echo "==> Checking a Mac that did not build this would open it"
MOUNT="$(mktemp -d)"
hdiutil attach -quiet -nobrowse -mountpoint "$MOUNT" "$DMG"
COPY="$(mktemp -d)/CCWidget.app"
cp -R "$MOUNT/CCWidget.app" "$COPY"
hdiutil detach -quiet "$MOUNT"

if spctl -a -vvv -t exec "$COPY" 2>&1 | sed 's/^/    /' | grep -q "accepted"; then
    echo "    Gatekeeper accepts it."
else
    echo "!! Gatekeeper refuses it. Nothing above caught that, which is why" >&2
    echo "   this check exists." >&2
    exit 1
fi

if xcrun stapler validate "$COPY" 2>&1 | grep -q "The validate action worked"; then
    echo "    The app carries its own ticket, so it opens offline too."
else
    echo "!! The app dragged out of the image has no ticket stapled to it." >&2
    echo "   It would need Gatekeeper to reach Apple on first launch." >&2
    exit 1
fi
rm -rf "$(dirname "$COPY")"

echo
echo "==> Done: $DMG"
echo "    Version $VERSION, commit $COMMIT, signed by $TEAM_ID, notarized and stapled."
echo "    This opens on a Mac that has never seen the source."
