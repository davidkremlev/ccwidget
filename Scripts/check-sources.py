#!/usr/bin/env python3
"""Checks SOURCES.md against the reference store it points at.

Two things go wrong with cached documentation, and neither announces itself.

It goes stale. A page fetched under macOS 26 keeps answering questions about
macOS 26 long after the machine has moved on, and it answers them in the same
confident voice as a fresh one. So: anything older than six months, or fetched
under a major version the machine has left behind, is reported.

And the table drifts from the store. SOURCES.md is a hand-written index of
files nobody edits by hand; a row can name a file that was never fetched, or
carry a date the store disagrees with, and the reader has no way to tell.
So the two are compared row by row.

This warns, it does not fail. A source past its date is a reason to re-read
it, not a reason to stop building — and on a CI machine there is no store at
all, which is reported and is not an error either.

    ./Scripts/check-sources.py
    ./Scripts/check-sources.py --store /somewhere/else --today 2027-01-01 --macos 27

Everything it needs from the outside — the store, the date, the system
version — arrives as an argument, so the checks below can be exercised
against a store that is deliberately stale without waiting six months or
upgrading anything.
"""

import argparse
import datetime
import json
import pathlib
import platform
import re
import sys

MAX_AGE_DAYS = 182  # six months

ROOT = pathlib.Path(__file__).resolve().parent.parent


def parse_table(text, heading):
    """Return the rows of the Markdown table under `heading`.

    Rows are dicts keyed by the header cells, which keeps this honest if a
    column is ever added: nothing is read positionally.
    """
    section = text.split("## " + heading, 1)
    if len(section) == 1:
        return None
    body = section[1].split("\n## ", 1)[0]
    rows, header = [], None
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if header is None:
            header = cells
        elif set("".join(cells)) <= set("-: "):
            continue
        else:
            rows.append(dict(zip(header, cells)))
    return rows


def major(version_text):
    """The macOS major version named in a string like 'macOS 26 / Xcode 26'."""
    m = re.search(r"macOS\s+(\d+)", version_text)
    return int(m.group(1)) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", default=str(pathlib.Path.home() / "Documents" / "refdocs"))
    ap.add_argument("--sources", default=str(ROOT / "SOURCES.md"))
    ap.add_argument("--today", default=datetime.date.today().isoformat())
    ap.add_argument("--macos", default=platform.mac_ver()[0].split(".")[0] or "0")
    args = ap.parse_args()

    today = datetime.date.fromisoformat(args.today)
    system_major = int(args.macos or 0)
    store = pathlib.Path(args.store)
    index_path = store / "index.json"

    text = pathlib.Path(args.sources).read_text()
    rows = parse_table(text, "Cached")
    mechanics = parse_table(text, "How it works")
    guidance = parse_table(text, "How to do it right")
    live = parse_table(text, "Read live, never cached")
    gaps = parse_table(text, "Where a genre is missing")
    if mechanics is None or guidance is None:
        print("::error::SOURCES.md is missing a genre table "
              "('How it works' / 'How to do it right')")
        return 1
    if live is None or gaps is None:
        print("::error::SOURCES.md is missing the live-sources or genre-coverage table")
        return 1
    rows = mechanics + guidance
    genre_of_row = ({r["Cached copy"]: "mechanics" for r in mechanics}
                    | {r["Cached copy"]: "guidance" for r in guidance})

    if not index_path.exists():
        # The normal case on a build machine. Say so rather than passing in
        # silence: a check that cannot run and does not mention it is
        # indistinguishable from a check that passed.
        print("notice: no reference store at %s — nothing to check against." % store)
        print("        %d rows in SOURCES.md were not verified." % len(rows))
        return 0

    index = json.loads(index_path.read_text())
    by_path = {e["path"]: e for e in index["sources"]}

    warnings = []
    for row in rows:
        path = row["Cached copy"].strip("`")
        entry = by_path.get(path)
        if entry is None:
            warnings.append("%s is listed in SOURCES.md but not in the store's index" % path)
            continue
        if not (store / path).exists():
            warnings.append("%s is indexed but the file is missing — run refdocs/_tools/fetch.py" % path)
            continue

        fetched = entry.get("fetched")
        if not fetched:
            warnings.append("%s has never been fetched" % path)
            continue
        if row["Fetched"] != fetched:
            warnings.append("%s: SOURCES.md says fetched %s, the store says %s"
                            % (path, row["Fetched"], fetched))
        if row["Version"] != entry["platform_version"]:
            warnings.append("%s: SOURCES.md says %s, the store says %s"
                            % (path, row["Version"], entry["platform_version"]))

        age = (today - datetime.date.fromisoformat(fetched)).days
        if age > MAX_AGE_DAYS:
            warnings.append("%s is %d days old — re-read it and re-fetch" % (path, age))

        pinned = major(entry["platform_version"])
        if pinned is not None and system_major and pinned < system_major:
            warnings.append("%s was fetched for macOS %d, this machine runs macOS %d"
                            % (path, pinned, system_major))

        # Which table a source sits in is a claim about what it can be cited
        # for. A reference page filed under "how to do it right" would be
        # quoted as advice it does not give.
        listed = genre_of_row.get(row["Cached copy"])
        if entry.get("genre") and listed != entry["genre"]:
            warnings.append("%s: SOURCES.md files it under %s, the store calls it %s"
                            % (path, listed, entry["genre"]))

    for path in sorted(set(by_path) - {r["Cached copy"].strip("`") for r in rows}):
        if "ccwidget" in by_path[path].get("projects", []):
            warnings.append("%s is in the store for this project but missing from SOURCES.md" % path)

    # A live source with no reading date is not connected. It is listed, which
    # looks like coverage, and nobody has opened it, which is the opposite.
    for row in live:
        when = row.get("Last read", "").strip()
        if when in ("", "—", "-"):
            warnings.append("live source never read: %s — the row claims coverage "
                            "the project does not have" % row.get("Link", "?"))
        else:
            try:
                age = (today - datetime.date.fromisoformat(when)).days
            except ValueError:
                warnings.append("live source %s has an unreadable date %r"
                                % (row.get("Area", "?"), when))
                continue
            if age > MAX_AGE_DAYS:
                warnings.append("live source %s was last read %d days ago"
                                % (row.get("Area", "?"), age))

    # Every area that appears in either genre table has to appear in the
    # coverage table too — that is where a missing genre gets stated in words
    # instead of being an empty space nobody notices.
    covered = {r["Area"] for r in gaps}
    for area in sorted({r["Area"] for r in rows}):
        if area not in covered:
            warnings.append("area %r has no row in 'Where a genre is missing'; "
                            "its second genre is neither present nor accounted for" % area)

    for w in warnings:
        print("::warning::%s" % w)

    print("%d cached sources listed, %d warnings." % (len(rows), len(warnings)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
