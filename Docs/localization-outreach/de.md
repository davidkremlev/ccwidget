<!--
Ready to post as an issue once the repository exists. Title and body are in
German on purpose: someone who reads German should not have to read an English
request first. Label it "help wanted" and pin it.

The link is absolute on purpose: posted as an issue, a relative one
resolves to nothing at all. It was relative until 17 August, and wrong in
both places — the repository and the issue.
-->

**Titel:** Deutsche Übersetzung: Muttersprachler:innen gesucht

---

`ccwidget` ist ein kleines Widget für den macOS-Schreibtisch. Es zeigt, wie viel
vom Claude-Kontingent verbraucht ist, wie voll das Kontextfenster gerade ist und
wann das Wochenkontingent voraussichtlich aufgebraucht sein wird.

Die Oberfläche gibt es in sechs Sprachen. Englisch und Russisch stammen von
Muttersprachlern, Deutsch nicht — ich habe es nach bestem Wissen selbst
übersetzt. **Genau dafür wäre eine Durchsicht Gold wert.**

Es geht nicht um eine Neuübersetzung, sondern um die zwei Dinge, die ein
Wörterbuch nicht erkennt: Sätze, die zwar korrekt sind, die aber niemand so
sagt — und ein Ton, der nicht passt. Ein Beispiel, das schon aufgefallen ist:
die Zeilenbeschriftung hieß ursprünglich `Woche genutzt`, was eine genutzte
Woche bedeutet und nicht „so viel der Woche ist verbraucht“. Sie heißt jetzt
`Diese Woche verbraucht`. Von dieser Sorte gibt es mit Sicherheit mehr.

Alle 112 Strings stehen in
[`Docs/localization-review.md`](https://github.com/davidkremlev/ccwidget/blob/main/Docs/localization-review.md), zusammen mit
dem Kontext, der die Wortwahl beeinflusst — zum Beispiel, dass alle drei
Balken in dieselbe Richtung wachsen und dass in einer Kachel von 338 Punkten
Breite nach etwa 22 Zeichen abgeschnitten wird.

**Eine Zeile in diesem Issue genügt:**

```
"Week used" (de) → "Diese Woche verbraucht" klingt besser als …
```

Kein Pull Request nötig, keine Swift-Kenntnisse. Wer lieber direkt ändert:
die Strings liegen als JSON in `App/Resources/Localizable.xcstrings` und
`Widget/Resources/Localizable.xcstrings`.

Vielen Dank — auch für einzelne Korrekturen. Eine gute Zeile ist mehr wert als
eine vollständige, aber hölzerne Übersetzung.
