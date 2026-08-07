#!/usr/bin/env python3
"""Regenerates Docs/localization-review.md from the string catalogs.

The document exists so that someone who reads German, Spanish, Japanese or
Simplified Chinese can review every string this app can show without cloning
anything or opening Xcode. That only works if it matches the catalogs, and a
hand-maintained copy of 112 strings would not for long — hence a generator
rather than a document.

    ./Scripts/localization-review.py

Run it after changing any user-facing string, the same way the screenshots get
re-shot after changing a view.
"""

import json
import pathlib

LANGUAGES = [("de", "German"), ("es", "Spanish"),
             ("ja", "Japanese"), ("zh-Hans", "Simplified Chinese")]

CATALOGS = [
    ("Widget/Resources/Localizable.xcstrings", "In the widget",
     "Seen on the desktop, in tiles 164 to 344 points wide."),
    ("App/Resources/Localizable.xcstrings", "In the app window",
     "Seen after clicking the widget, and during setup."),
]

PREAMBLE = """# Localization review

The interface ships in six languages. **English and Russian are first-language
work. German, Spanish, Japanese and Simplified Chinese are not** — they are one
developer's best effort, and they want a native speaker's eye before anyone
relies on them.

This file is generated from the string catalogs by
`./Scripts/localization-review.py`. Edit the catalogs, not this.

## What is being asked

Not a translation project. A read-through, looking for the two things a
dictionary cannot catch:

1. **Sentences nobody says.** A translation can be word-for-word correct and
   still read like a machine wrote it. This has already happened here: the row
   captions used to be `Woche genutzt` in German and `Semana usada` in Spanish,
   both of which mean "a week that was used" rather than "how much of the week
   you have used". They were rewritten after reading them aloud.
2. **Wrong register or wrong term.** This is a small utility that sits on a
   desktop. It should sound like a tool, not like a legal notice or a chat
   message.

## How to send corrections

Open an issue with the key and what it should say. One line is plenty:

```
"Week used" (de) → "Diese Woche verbraucht" reads better as "…"
```

No pull request is needed and no Swift. If you would rather edit directly, the
strings are plain JSON in `App/Resources/Localizable.xcstrings` and
`Widget/Resources/Localizable.xcstrings`, in Apple's String Catalog format.

## Context that changes the wording

- **The three gauge rows all measure consumption**, and all three grow towards
  worse. Whatever they say, more must sound worse — not "70 % remaining" in one
  row and "30 % used" in another.
- **The context window is filled, not spent.** It is not a subscription quota
  and hitting 100 % costs nothing; it means the model starts losing the
  beginning of the conversation. Russian uses a different verb for that row for
  exactly this reason.
- **Space is tight.** A widget tile is 164 or 344 points wide. The medium size
  fits a caption of roughly 22 characters beside a bar and a number; longer
  captions shrink and then truncate. Shorter is better when the choice is
  between shorter and more precise.
- **"Status line"** is the Claude Code feature that feeds this widget — the
  line the CLI redraws under the prompt. It is a proper feature name.
- **"Snapshot", "exporter", "exchange directory", "watcher"** are this
  project's own terms for its parts, defined in `SPEC.md`. Consistency between
  them matters more than elegance in any one.

---

## The strings

`%@` and `%lld` are substituted at runtime — keep them, and keep their order
where the grammar allows. Plural forms are shown as `one:` / `other:` and so
on; a language that needs more categories than are listed is itself a finding.

"""


def rendered(localizations: dict, language: str) -> str:
    entry = localizations.get(language, {})
    if "stringUnit" in entry:
        return entry["stringUnit"]["value"]
    if "variations" in entry:
        plural = entry["variations"].get("plural", {})
        return "  ·  ".join(f"_{name}_: {form['stringUnit']['value']}"
                            for name, form in sorted(plural.items()))
    return "—"


def escaped(text: str) -> str:
    return text.replace("|", "\\|")


def main() -> None:
    root = pathlib.Path(__file__).resolve().parent.parent
    out = [PREAMBLE]

    for path, title, note in CATALOGS:
        catalog = json.loads((root / path).read_text())
        out.append(f"### {title}\n\n{note}\n")
        for key in sorted(catalog["strings"], key=str.lower):
            string = catalog["strings"][key]
            localizations = string.get("localizations", {})
            comment = string.get("comment")
            out.append(f"\n**`{escaped(key)}`**" + (f" — {comment}" if comment else "") + "\n")
            out.append("| | |\n|---|---|")
            for code, name in LANGUAGES:
                out.append(f"| {name} | {escaped(rendered(localizations, code))} |")
            out.append("")

    total = sum(len(json.loads((root / p).read_text())["strings"]) for p, _, _ in CATALOGS)
    out.append(f"\n---\n\n{total} strings in total.\n")
    (root / "Docs/localization-review.md").write_text("\n".join(out))
    print(f"Docs/localization-review.md — {total} strings")


if __name__ == "__main__":
    main()
