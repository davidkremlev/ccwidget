# Security policy

## Reporting a vulnerability

Report privately through GitHub's **[Report a vulnerability](../../security/advisories/new)**
form. Do not open a public issue for a security problem.

If GitHub Security Advisories are unavailable to you, open a normal issue that
says only *"security report, please provide a private channel"* — without any
detail — and a contact will be arranged from there.

**What to expect:**

| | |
|---|---|
| First reply | within 7 days |
| Assessment and severity | within 14 days of the first reply |
| Fix for a confirmed high-severity issue | targeted within 30 days |
| Public disclosure | after a fix ships, credited unless you prefer otherwise |

This is a single-maintainer hobby project, not a funded product. Those windows
are what one person can realistically hold to, not a service-level agreement.
If a deadline slips you will be told, and told why.

## What is in scope

The parts of this project that touch your machine:

- **The exporter** (`Scripts/ccwidget-export.py.template`) — it runs on every
  status line redraw with your privileges. Anything that lets it write outside
  its exchange directory, follow a symlink, execute injected code, or consume
  unbounded resources is in scope.
- **The installer** (`App/Installer.swift`, `App/SettingsEditor.swift`) — it
  edits `~/.claude/settings.json` and writes an executable script. Anything
  that corrupts the config, escapes the intended paths, or installs without an
  explicit user action is in scope.
- **The exchange format** — anything in `snapshot.json` or `history.jsonl` that
  discloses more than intended, or that can crash or hang the widget when
  malformed.
- **Log privacy** — user paths, project names or raw field values reaching the
  unified log as `.public`.

## What is out of scope

- **Attacks requiring an attacker who already runs code as you.** Such an
  attacker can edit `~/.claude/settings.json` directly. Report it anyway if
  this project *amplifies* that position — for example by turning it into a
  repeated write to files elsewhere — but plain "same-user process can do X"
  is not a finding here.
- **The absence of Developer ID signing and notarization.** Known, documented,
  and tracked separately.
- **Anything about Claude Code or Anthropic's services.** Report those to
  Anthropic. This project only reads a file Claude Code hands to it.

## Threat model in one paragraph

This project has no network code, no credentials, and no privileged helper. It
reads a JSON blob that Claude Code pipes to a status line command, writes two
files into the widget extension's own container, and renders them. The
security-relevant surface is therefore *file handling* and *config editing* —
not authentication, not transport, not cryptography. Findings that matter are
the ones where a file gets written somewhere it should not, or where the
config is left broken.
