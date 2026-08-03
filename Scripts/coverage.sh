#!/bin/bash
#
# Reports test coverage of the production code.
#
# Two things this does that `xccov view --report` on its own does not.
#
# It drops Tests/ from the total. Test files run by definition, so counting
# them inflates the figure by a third and flatters exactly the code that needs
# no confidence.
#
# And it counts each source file once. Shared/ is compiled into all three
# targets, so the same file appears three times in the raw report with three
# different numbers, of which only the highest means anything: a line covered
# in any target is a line that ran.
#
#   ./Scripts/coverage.sh                     # run the tests, then report
#   ./Scripts/coverage.sh --no-run            # report on the last run
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${DERIVED_DATA:-$ROOT/.build/dd}"
RUN=1
[ "${1:-}" = "--no-run" ] && RUN=0

if [ "$RUN" -eq 1 ]; then
    xcodebuild \
        -project "$ROOT/CCWidget.xcodeproj" \
        -scheme CCWidget \
        -configuration Debug \
        -derivedDataPath "$DERIVED" \
        -enableCodeCoverage YES \
        test \
        | grep -E "error:|✘|Test run|TEST" || true
fi

# `|| true` is not decoration. With `set -e` and `pipefail`, a glob that
# matches nothing makes this assignment fail, and the script exits silently
# with status 1 — swallowing the very message written for this case, which is
# the one anybody running --no-run before a test run will hit.
RESULT="$(ls -td "$DERIVED"/Logs/Test/*.xcresult 2>/dev/null | head -1 || true)"
if [ -z "$RESULT" ]; then
    echo "!! No test result bundle under $DERIVED/Logs/Test" >&2
    exit 1
fi

xcrun xccov view --report --json "$RESULT" > "$DERIVED/coverage.json"

python3 - "$DERIVED/coverage.json" <<'PY'
import json, sys

report = json.load(open(sys.argv[1]))

# path -> (covered, executable), keeping the best result across targets
best = {}
for target in report["targets"]:
    for entry in target["files"]:
        name = entry["path"].split("ccwidget/")[-1]
        covered, total = entry["coveredLines"], entry["executableLines"]
        if name not in best or covered > best[name][0]:
            best[name] = (covered, total)

production = {k: v for k, v in best.items() if not k.startswith("Tests/")}
covered = sum(v[0] for v in production.values())
total = sum(v[1] for v in production.values())
percent = 100 * covered / total if total else 0

rows = sorted(production.items(), key=lambda kv: (kv[1][0] / kv[1][1] if kv[1][1] else 0, -kv[1][1]))
width = max(len(k) for k in production)

print()
print(f"Coverage of production code: {percent:.1f}%  ({covered}/{total} lines)")
print()
for name, (c, t) in rows:
    print(f"  {name.ljust(width)}  {100 * c / t if t else 0:6.1f}%  {c:5}/{t}")

untouched = [(n, t) for n, (c, t) in rows if c == 0]
if untouched:
    print()
    print(f"Never executed by any check ({sum(t for _, t in untouched)} lines):")
    for name, t in untouched:
        print(f"  {name}  ({t} lines)")

# Machine-readable, for a CI job summary
with open(sys.argv[1].replace(".json", ".txt"), "w") as f:
    f.write(f"{percent:.1f}\n")
PY
