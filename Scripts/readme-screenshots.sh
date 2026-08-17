#!/bin/bash
#
# Re-shoots the six README screenshots.
#
# They used to come from the developer's live snapshot, which put a real
# session cost and a real week's usage into a public README and made the
# pictures whatever that afternoon happened to look like. One of them showed
# the estimate saying "Not enough data yet", because the shots were taken just
# after a weekly reset — the product's one distinctive feature, photographed at
# its least convincing.
#
# So the data is made up now, and made up here rather than committed: the
# countdown in a row is a *dynamic date*, drawn by the system from the real
# clock and not from the moment the entry carries. A fixture with fixed
# timestamps therefore renders "2 yrs, 9 mths" — measured, and it is the same
# trap RowCompositionTests documents. The fixture has to be written relative to
# now, every time, which means it is a generator and not a file.
#
#   ./Scripts/readme-screenshots.sh              # into Docs/screenshots
#   ./Scripts/readme-screenshots.sh /tmp/shots   # somewhere else, to compare
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/Docs/screenshots}"
TOOL="$ROOT/.build/ccwidget-screenshots"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

echo "==> Building the renderer"
swiftc -swift-version 6 -strict-concurrency=complete -target arm64-apple-macos14.0 \
    "$ROOT"/Shared/*.swift \
    "$ROOT"/Widget/Provider.swift "$ROOT"/Widget/Components.swift \
    "$ROOT"/Widget/ForecastChart.swift "$ROOT"/Widget/SmallView.swift \
    "$ROOT"/Widget/MediumView.swift "$ROOT"/Widget/LargeView.swift \
    "$ROOT"/Tools/ccwidget-screenshots/main.swift -o "$TOOL"

NOW="$(date +%s)"

echo "==> Writing a fixture relative to now"
python3 - "$FIXTURE" "$NOW" <<'PY'
import json, random, sys

fixture, now = sys.argv[1], int(sys.argv[2])
week_reset = now + 3 * 86_400        # three days out
five_reset = now + 94 * 60           # 1 hr 34 min

# Forty hours of history rising a point an hour, which is what makes the
# estimate able to name a date at all: ten points minimum, two hours minimum,
# R² above 0.7, and exhaustion inside ten times the span the weighting reaches.
# At 47 % and a point an hour it runs out in 53 hours, comfortably before the
# reset — so the picture shows `Runs out ~…` rather than `Lasts until reset`.
random.seed(11)
rate, hours, step = 1.0, 40, 1800
start = 47 - rate * hours
points = []
for i in range(hours * 3600 // step + 1):
    value = start + rate * (i * step / 3600) + random.uniform(-0.4, 0.4)
    points.append({"t": now - hours * 3600 + i * step,
                   "sevenDay": max(0, round(value)),
                   "resetsAt": week_reset})
points[-1]["sevenDay"] = 47

snapshot = {
    "schemaVersion": 1,
    "capturedAt": now,
    "sessionId": "5e551047",
    "claudeCodeVersion": "2.1.223",
    "model": {"id": "claude-opus-5", "displayName": "Opus 5 (1M context)", "effort": "high"},
    "project": {"name": "ccwidget"},
    "limits": {"fiveHour": {"usedPercentage": 22, "resetsAt": five_reset},
               "sevenDay": {"usedPercentage": 47, "resetsAt": week_reset}},
    "context": {"usedPercentage": 68, "totalInputTokens": 683_120,
                "windowSize": 1_000_000, "cacheHitRatio": 0.9917},
    "cost": {"sessionUsd": 12.4},
}
with open(fixture + "/snapshot.json", "w") as f:
    json.dump(snapshot, f)
with open(fixture + "/history.jsonl", "w") as f:
    for p in points:
        f.write(json.dumps(p) + "\n")
print(f"    {len(points)} points over {hours} h, week at 47 %, rising {rate} %/h")
PY

echo "==> Shooting"
# The locale is explicit because the README is in English while numbers and
# dates follow the system region; the zone is UTC so the times in the pictures
# are not somebody's city.
"$TOOL" "$OUT" --fixture "$FIXTURE" --now "$NOW" --time-zone UTC \
    -AppleLocale en_US -AppleLanguages "(en)"

echo
echo "==> Look at them before committing. What to check:"
echo "    · no countdown reading in years — that means the fixture and the"
echo "      system clock have drifted apart and the dynamic dates are nonsense"
echo "    · the estimate names a rate and a date, not \"Not enough data yet\""
echo "    · nothing clipped, no ellipsis at the end of a line"
