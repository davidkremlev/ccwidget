# Security and privacy audit, 7 August 2026

Run by a reviewer with no knowledge of the project's history — a separate model,
a clean context, read-only. It was asked to find holes, not to fix them.

The full report follows as received, with only formatting normalised. Nothing in
it was edited when findings were closed; what has been acted on is listed here
instead.

## What has been acted on

| # | State | Where |
|---|-------|-------|
| 1 | **Closed** on 16 August 2026 | `Scripts/uninstall.sh` compares `statusLine.command` exactly, the way the app always has, and keeps the exporter file when anything else in `settings.json` still names it. Checked by `Scripts/check-uninstall.sh`, which fails sixteen of its fifty-seven assertions against the old script. |
| 3 | **Open** — the app half is the finding | The report already exempts the script's `cp`. Its backup is now opened `0600` outright rather than relying on `cp` to carry the mode over, but the finding itself is about `Installer.backupSettings`, and that is untouched. |
| 8 | **Closed** | The uninstaller writes a neighbouring file and renames it over the original. |

Everything else stands as reported.

---

## Findings, worst first

### 1. `Scripts/uninstall.sh` can delete a `statusLine` that is not ours

**Where:** `Scripts/uninstall.sh:47` (`grep -q "ccwidget-export.py" "$SETTINGS"`)
and lines 101–104 (`del data["statusLine"]`).

The shell uninstaller decides "the statusLine is ours" by grepping the whole
settings file for the substring `ccwidget-export.py`, then deletes
`data["statusLine"]` unconditionally.

A user whose statusLine is a wrapper chaining the exporter with their own, or
whose settings mention the exporter path under any other key, loses their own
configuration. The app-side uninstall (`App/Installer.swift:456`,
`statusLineState() == .ours`) requires an exact match on `command`; the script —
the fallback for when the app is gone — is strictly weaker. The project's own
charter forbids silently clobbering a foreign `statusLine`; this is the
removal-side violation of that rule.

**Severity: medium.** Destroys user configuration; mitigated by the backup and
the confirmation prompt — but the prompt asserts "others untouched" and never
says the match was a substring guess.

### 2. The reader has no size limit, despite a documented incident

**Where:** `Shared/SnapshotStore.swift:171`, `Shared/HistoryStore.swift:37,69`.

`load()` reads `snapshot.json` whole with `Data(contentsOf:)`; the history is
read whole with `String(contentsOf:)`. No size or nesting cap on the read side.

The exporter template itself records (lines 9–11) that "a gigabyte of input
landed in the snapshot whole and killed the widget extension on read." The fix
was applied only at the writer (`MAX_INPUT = 1 << 20`). Any other writer — a
second tool, a future exporter bug, any same-user process — reproduces the
crash on every render, and the widget shows a stale frame that looks merely old.

**Severity: low–medium.** Local, denial-of-widget only. The rating rests on it
being a recurrence path for a defect this project has already suffered once.

### 3. The settings backup is briefly world-readable

**Where:** `App/Installer.swift:342–347`.

`backupSettings()` writes with `Data.write(.atomic)` — mode 644 — and chmods to
600 afterwards. The adjacent comment says why that is wrong: "settings.json can
hold environment variables and keys. The backup must be no more readable than
the original." Between the write and `setAttributes`, and permanently if the
process dies in between, the backup is 644. On this machine `~/.claude` is 755
and the home directory is `drwxr-x---` group `staff`, and every local user is in
`staff`.

Verified by probe: a fresh atomic write lands at 644; an atomic rewrite of an
existing 600 file keeps 600 — so the main settings write is safe, the backup is
not. `uninstall.sh:86–87` has the same shape, but `cp` preserves the source
mode.

**Severity: low.** Small window, multi-user Macs only — on exactly the file the
project classifies as key-bearing.

### 4. "Remove history" leaves `export-skipped.json` behind

**Where:** `App/Installer.swift:484–488`; written by
`Scripts/ccwidget-export.py.template:111–131`.

`uninstall(removingHistory: true)` deletes `history.jsonl` and `snapshot.json`
but not `export-skipped.json`, which carries an 8-character `sessionId` prefix
and a timestamp. The user asked for their data to be removed and a session
identifier fragment survives; the file is also in nobody's `manualLeftovers`
list, so the removal report does not mention it. `uninstall.sh --purge` is
unaffected — it removes the whole container.

**Severity: low.**

### 5. The exporter integrity check claims more than it delivers

**Where:** `App/Installer.swift:92–97` (claim), `169–175` (check).

The SHA-256 of the installed exporter lives in `~/.claude/.ccwidget-export.sha256`
— the same user-writable directory as the exporter — and the comment says the
hash "makes tampering visible." Anyone able to replace the exporter can rewrite
the hash beside it with the same privileges. The check detects accidental drift,
not tampering.

**Severity: informational.** No behaviour is wrong; the documented security
property is overstated — which the project's own charter treats as worse than
saying nothing, because the next reader trusts it.

### 6. One public log field is built from arbitrary error interpolation

**Where:** `Shared/Diagnostics.swift:42–44` and `55–68`.

`DiagnosticsCollector.record` logs `reason` as `.public`, and `reason(for:)`
falls through to `"\(error)"` for non-`DecodingError` errors and for
`@unknown default`. Today every caller passes `DecodingError`s, whose
descriptions carry type names and key paths rather than values — so the "raw
values are private" claim currently holds, and no counterexample was found. But
the CI sentinel greps only for `path|Path|home|NSHomeDirectory|rawValue` beside
`.public`, and would not catch `reason`.

**Severity: informational.** A latent channel, not a present leak.

### 7. `pruneBackups` deletes files it did not create

**Where:** `App/Installer.swift:356–367`.

Every file in `~/.claude` whose name starts with `settings.json.bak-` beyond the
newest five is deleted, whoever made it. A user keeping their own
`settings.json.bak-before-experiment` loses it silently on the sixth install.

**Severity: low.**

### 8. `uninstall.sh` rewrites settings.json non-atomically

**Where:** `Scripts/uninstall.sh:119–125`.

The embedded Python writes with `open(path, "w")` — truncate then write. A crash
mid-write leaves a truncated `settings.json`. The backup makes it recoverable,
and the app-side writer is atomic for the same file.

**Severity: low.**

---

## Examined and found clean

- **The whole git history, 75 commits (`git log --all -p`):** no home paths, no
  emails, no tokens or keys, no team IDs or signing identities; the
  briefly-committed `CCGauge.xcodeproj` carried `CODE_SIGN_IDENTITY = "-"` and an
  empty `DEVELOPMENT_TEAM`. The committed-then-removed `default.profraw` was zero
  bytes. Only the intentionally public GitHub handle appears. Fixtures are
  synthetic. `Docs/estimate-review.md` publishes the owner's own aggregate usage
  percentages — deliberate and non-identifying.
- **Template injection:** `pythonStringLiteral` substitutes a finished
  JSON-escaped literal and is verified by a round-trip test that decodes it back
  to the original path — the property, not a proxy. Shebang substitution takes
  fixed absolute interpreter paths only.
- **Symlink and TOCTOU handling:** the exporter uses `O_NOFOLLOW|O_EXCL` with
  unlink-first and `os.replace`; app-side truncation does the same and is
  regression-tested with a planted symlink; the installer resolves `settings.json`
  symlinks and backs up as a plain file. One residual, robustness rather than
  security: two concurrent exporters can race on `snapshot.json.tmp` and produce a
  torn snapshot, which the reader tolerates and the next write heals.
- **Exporter input boundaries:** 1 MB stdin cap, type-checked root, tolerant
  numeric parsing, everything wrapped so the status line cannot break — with the
  skip notice so silence stays observable.
- **What the snapshot stores:** session ID truncated to 8 characters, project
  reduced to a basename with no field for the full path, history holding only
  timestamps and percentages, files 0600. Every stored field is displayed
  somewhere.
- **Network:** none anywhere in App, Shared or Widget, and CI enforces it.
- **Config editing:** the surgical editor re-parses and compares against the
  expected object before accepting an edit; rewrite is the declared, reported
  fallback; a foreign `statusLine` is respected on the app path — finding 1 is the
  script-path exception.
