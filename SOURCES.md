# Sources of truth

This project says a great many things about how other people's systems
behave — that WidgetKit spends a budget, that a sandboxed process sees its
container as its home, that `os.replace` lands atomically, that a status line
receives a percentage as an integer. Every one of those is a claim, and a
claim believed on the strength of an analogy is the cheapest defect there is
to write and the dearest to find.

**The rule this file exists for lives in `CLAUDE.md`: a claim about the
platform cites a source from here, or is marked as unverified. There is no
third option.**

The documents themselves are not in this repository — they are somebody
else's copyrighted work, and a public repository is not where they belong.
They are cached locally, one store shared by every project on the machine:

    ~/Documents/refdocs/

Fill or refresh it with `~/Documents/refdocs/_tools/fetch.py`, which writes
each file's origin and date into `index.json`. Check that the tables below
still match the store with `./Scripts/check-sources.py`.

Apple's documentation site serves an empty shell to a fetcher; its real
content comes from the DocC JSON behind it, which is what the fetcher reads
and renders. The cached files are Apple's own prose restructured, not a
summary of it. Anything the converter wrote itself — a heading it chose, a
label it invented, the footer — carries the marker `⟦refdocs⟧` in the cached
file. **Quote the unmarked text; never the marked.**

## Two genres, and why both are needed

A source says either **how something works** or **how it is meant to be
used**, and the two are not interchangeable. `TimelineProvider`'s reference
page tells you what a timeline is; nothing on it tells you that a widget
which redraws every minute is the wrong shape of widget. A project holding
only the first kind knows every API and can still build the wrong thing
correctly.

Until this file was split, the store held twenty-four sources and not one of
the second kind. That was not a shortage of documents — Apple publishes them
— it was nobody having asked the question.

## How it works

| Area | Cached copy | Answers | Fetched | Version |
|---|---|---|---|---|
| WidgetKit | `apple/widgetkit-keeping-up-to-date.md` | timelines, reload policies, the refresh budget and what the system does when it is spent | 2026-08-06 | macOS 26 / Xcode 26 |
| WidgetKit | `apple/widgetkit-widgetcenter.md` | `reloadAllTimelines()` — how an app asks for a reload | 2026-08-06 | macOS 26 / Xcode 26 |
| WidgetKit | `apple/widgetkit-widgetfamily.md` | which families exist on macOS and since when | 2026-08-06 | macOS 26 / Xcode 26 |
| WidgetKit | `apple/widgetkit-creating-a-widget-extension.md` | the shape of an extension: configuration, provider, entry | 2026-08-06 | macOS 26 / Xcode 26 |
| WidgetKit | `apple/widgetkit-timelinereloadpolicy.md` | `atEnd`, `never`, `after(_:)` | 2026-08-06 | macOS 26 / Xcode 26 |
| WidgetKit | `apple/widgetkit-updates.md` | what changed in WidgetKit per OS release — when an API or behaviour arrived | 2026-08-06 | macOS 26 / Xcode 26 |
| Sandbox | `apple/security-app-sandbox.md` | what the sandbox restricts, what a container is | 2026-08-06 | macOS 26 |
| Sandbox | `apple/security-sandbox-file-access.md` | which paths a sandboxed process may read and write | 2026-08-06 | macOS 26 |
| Sandbox | `apple/entitlement-app-sandbox.md` | the entitlement key itself and its type | 2026-08-06 | macOS 26 / Xcode 26 |
| Sandbox | `apple/foundation-nshomedirectory.md` | what `NSHomeDirectory()` returns inside a sandbox and outside one | 2026-08-06 | macOS 26 |
| Distribution | `apple/security-hardened-runtime.md` | hardened runtime capabilities and their cost | 2026-08-06 | macOS 26 / Xcode 26 |
| Distribution | `apple/security-notarization.md` | notarization: requirements, the stamp, Gatekeeper's check | 2026-08-06 | macOS 26 / Xcode 26 |
| Rendering | `apple/swiftui-imagerenderer.md` | rendering a view off screen: `scale`, `colorMode`, PDF output | 2026-08-06 | macOS 26 |
| Watching files | `apple/dispatch-dispatchsource.md` | file system object sources and the events they deliver | 2026-08-06 | macOS 26 |
| Watching files | `apple/dispatch-filesystemevent.md` | the event set itself: `delete`, `rename`, `write`, `extend`, `attrib`, `link`, `funlock` | 2026-08-07 | macOS 26 |
| Localization | `apple/xcode-string-catalog.md` | `.xcstrings`: extraction, plural and device variations | 2026-08-06 | Xcode 26 |
| Logging | `apple/os-logging.md` | the unified log: levels, subsystems, categories, persistence | 2026-08-06 | macOS 26 |
| Logging | `apple/os-log-messages.md` | privacy of interpolated values — `.public`, `.private`, the default | 2026-08-06 | macOS 26 |
| Checks | `apple/swift-testing.md` | `@Test`, `#expect`, suites, traits, parameterized cases | 2026-08-06 | Xcode 26 |
| Icon | `apple/xcode-icon-composer.md` | the `.icon` format, layers, how a target names its icon | 2026-08-06 | Xcode 26 |
| Accessibility | `apple/swiftui-accessibility.md` | accessibility modifiers: label, value, element combination | 2026-08-06 | macOS 26 |
| Claude Code | `claude-code/statusline.md` | the JSON handed to a status line: every field, its type, when it is absent or null | 2026-08-06 | Claude Code 2.1.223 |
| Claude Code | `claude-code/settings.md` | `~/.claude/settings.json`: keys, the shape of `statusLine`, precedence | 2026-08-06 | Claude Code 2.1.223 |
| Exporter | `python/os-replace.md` | `os.replace`: atomicity of the rename and its caveats | 2026-08-06 | Python 3.14 |
| Build | `tooling/xcodegen-projectspec.md` | every key `project.yml` may contain | 2026-08-06 | XcodeGen master |
| Background | `apple/servicemanagement-smappservice.md` | registering an app to run at login, and the statuses it can be in | 2026-08-17 | macOS 26 |
| Background | `apple/appkit-launch-user-info-keys.md` | whether a launch was a person or something else starting the app | 2026-08-17 | macOS 26 |
| Background | `apple/servicemanagement-status.md` | what each registration state of a login item means — and the one place this store disagrees with what the framework does | 2026-08-17 | macOS 26 |
| Background | `apple/appkit-didfinishlaunching.md` | what the launch notification carries | 2026-08-17 | macOS 26 |
| Build | `apple/xcode-26-release-notes.md` | which macOS version Xcode 26 requires, and what it ships SDKs for | 2026-08-16 | Xcode 26 |
| Liquid Glass | `apple/swiftui-liquid-glass-custom-views.md` | `glassEffect`, `GlassEffectContainer`, the glass button styles: how a custom SwiftUI view takes on the material | 2026-08-18 | macOS 26 / Xcode 26 |
| Liquid Glass | `apple/swiftui-glasseffect.md` | the `glassEffect(_:in:)` modifier: parameters and availability (macOS 26 and later) | 2026-08-18 | macOS 26 / Xcode 26 |
| Liquid Glass | `apple/swiftui-glasseffectcontainer.md` | `GlassEffectContainer`: grouping glass views so that they blend and animate together | 2026-08-18 | macOS 26 / Xcode 26 |
| Liquid Glass | `apple/appkit-nsglasseffectview.md` | `NSGlassEffectView`: AppKit's glass view — `contentView`, `cornerRadius`, `style`, `tintColor`. Consulted for a glass window background on 18 August 2026 and **rejected on measurement**: it refracts only what is inside its own window; behind a transparent window, and over a behind-window blur, it draws opaque. What the reference page does not say and the store now does | 2026-08-18 | macOS 26 / Xcode 26 |
| Liquid Glass | `apple/appkit-nsglasseffectview-style.md` | the two glass styles, `regular` and `clear` — both measured opaque as a window background, see above | 2026-08-18 | macOS 26 / Xcode 26 |
| Liquid Glass | `apple/appkit-nsvisualeffectview.md` | `NSVisualEffectView`: the pre-glass translucent materials; `.behindWindow` does show the desktop through a transparent window — measured the same day, and it is a material, not Liquid Glass. Not used: the owner chose the opaque window, which is what Apple's adoption guide describes | 2026-08-18 | macOS 26 |
| Layout | `apple/swiftui-grid.md` | `Grid`: columns take the width of their widest cell; what a non-row element becomes; how flexible cells share space | 2026-08-18 | macOS 26 / Xcode 26 |
| Layout | `apple/swiftui-gridrow.md` | `GridRow`: cells of a row; a modifier on a row applies to every cell, like a `Group` | 2026-08-18 | macOS 26 / Xcode 26 |
| Layout | `apple/swiftui-gridcolumnalignment.md` | `gridColumnAlignment(_:)`: aligning a whole column | 2026-08-18 | macOS 26 / Xcode 26 |

## How to do it right

| Area | Cached copy | Answers | Fetched | Version |
|---|---|---|---|---|
| WidgetKit | `apple/widgetkit-strategy.md` | which widget features to adopt and in what order; what a widget is for | 2026-08-06 | macOS 26 / Xcode 26 |
| WidgetKit | `apple/widgetkit-swiftui-views.md` | which SwiftUI views are usable in a widget, and that UIKit/AppKit wrappers are not | 2026-08-06 | macOS 26 / Xcode 26 |
| WidgetKit | `apple/widgetkit-creating-views.md` | how a widget's views are meant to be built: layout, margins, backgrounds | 2026-08-06 | macOS 26 / Xcode 26 |
| WidgetKit | `apple/widgetkit-dynamic-dates.md` | showing a countdown or relative time without spending a timeline reload | 2026-08-07 | macOS 26 / Xcode 26 |
| Accessibility | `apple/accessible-descriptions.md` | how a widget describes itself to VoiceOver: labels, order, what to hide | 2026-08-06 | macOS 26 / Xcode 26 |
| Accessibility | `apple/hig-voiceover.md` | what VoiceOver expects: labels, grouping, reading order, which images may be hidden | 2026-08-07 | macOS 26 |
| Typography | `apple/hig-typography.md` | the built-in text styles and their point sizes per platform, and each platform's minimum | 2026-08-07 | macOS 26 |
| Icon | `apple/hig-app-icons.md` | how an app icon is supposed to look: layers, shape, legibility, what not to put in it | 2026-08-06 | macOS 26 |
| Concurrency | `tooling/swift6-data-race-safety.md` | what `complete` checking asks of you: `Sendable`, isolation domains | 2026-08-06 | Swift 6 |
| Liquid Glass | `apple/liquid-glass-adopting.md` | what the system applies on its own when built with the macOS 26 SDK; where custom glass belongs (controls, the toolbar layer) and where it does not (content); "sparingly"; a label for every toolbar icon | 2026-08-18 | macOS 26 / Xcode 26 |

## Read live, never cached

**Last read is part of the source.** A link nobody has opened is an
intention, not a source: an empty cell here means this project has never
consulted the page and may not cite it. The column is filled during an audit,
by the person who read it.

| Area | Genre | Link | Last read | Why not cached |
|---|---|---|---|---|
| Widget layout | how to do it right | <https://developer.apple.com/design/human-interface-guidelines/widgets> | 2026-08-06 | guidance changes without notice and without a version to pin — including the size table section 9 depends on |
| Accessibility (overview) | how to do it right | <https://developer.apple.com/design/human-interface-guidelines/accessibility> | 2026-08-06 | same. Note: the VoiceOver guidance moved off this page on 7 March 2025 and is now cached as `apple/hig-voiceover.md` — this page is the overview only |
| Materials (Liquid Glass) | how to do it right | <https://developer.apple.com/design/human-interface-guidelines/materials> | 2026-08-18 | same. The adoption guide (cached) carries the rules this project acts on; the HIG page is the design rationale behind them |
| Consumer Terms | how it works | <https://www.anthropic.com/legal/consumer-terms> | 2026-08-06 | a legal document; section 14 of `SPEC.md` turns on its clause 3.7, and a stale copy of a legal text is worse than none |
| Usage policy | how it works | <https://www.anthropic.com/legal/aup> | 2026-08-06 | legal document |
| Homebrew | how to do it right | <https://docs.brew.sh/Cask-Cookbook> | 2026-08-06 | the policy of a repository that moves |
| App extensions | how it works | <https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionCreation.html> | 2026-08-07 | Apple's archive: retired, not updated for macOS 26, and the only place that states an extension's icon must be its containing app's. Cite it as archive, and re-check before relying on anything else from it |

## Where a genre is missing

Written out rather than left blank: an area with one genre and a silent gap
looks identical to an area where the missing genre does not exist.

| Area | How it works | How to do it right | What that means |
|---|---|---|---|
| WidgetKit | ✓ 6 | ✓ 3 + HIG live | complete |
| Accessibility | ✓ 1 | ✓ 1 + HIG live | complete |
| Concurrency | — | ✓ 1 | the mechanics are the language itself; *The Swift Programming Language* is the reference and is not cached. Connect it if a claim ever turns on language semantics rather than on the migration rules |
| Liquid Glass | ✓ 6 | ✓ 1 + HIG live | complete; three of the six record a measurement the reference pages do not carry
| Layout | ✓ 3 | — | none published for `Grid` beyond the reference; the layout rules this project follows are its own, section 9 |
| Sandbox | ✓ 4 | — | Apple's App Sandbox Design Guide has been retired and its URL 404s. The reference pages are all that remains published; treat design decisions here as our own, not as Apple's advice |
| Distribution | ✓ 2 | — | no separate guidance is published; the notarization page carries what advice there is |
| Icon | ✓ 1 | ✓ 1 | complete. HIG App icons is cached rather than read live: unlike the widget layout guidance it is referenced for facts about layers and shape, and a claim needs a copy that can be quoted |
| Localization | ✓ 1 | **not connected** | <https://developer.apple.com/design/human-interface-guidelines/writing> and `/inclusion` exist. `Docs/localization-review.md` asks native speakers for exactly the judgement these pages describe |
| Logging | ✓ 2 | — | the privacy rules are in the reference page itself; no separate guide is published |
| Typography | — | ✓ 1 | the mechanics are SwiftUI's `Font`, whose reference page is not cached; the sizes that matter here are the platform tables in the HIG page |
| Rendering | ✓ 1 | — | none published — `ImageRenderer`'s page is the whole of it |
| Watching files | ✓ 1 | — | none published |
| Checks | ✓ 1 | — | Swift Testing publishes no separate guidance page; `/documentation/testing/writingtests` does not exist |
| Claude Code | ✓ 2 | **not connected** | <https://docs.claude.com/en/docs/claude-code/best-practices> exists. Relevant to how the exporter and the status line integration are shaped, not to the JSON schema |
| Exporter | ✓ 1 | — | none applies: the claim we make about Python is one function's atomicity |
| Background | ✓ 4 | — | none published: Apple documents the API and says nothing about how an app that runs at login should behave. That it must not open a window is our judgement, not their guidance |
| Build | ✓ 2 | — | XcodeGen documents its schema and offers no guidance beyond it; Xcode's release notes carry the toolchain's own requirements |

Two of these are gaps to close, not facts of nature: **Localization** and
**Claude Code** each have a published guidance document that this project has
never opened. The third, **Icon**, was one until the HIG page was connected.

## What has no source

Named here so that nobody goes looking for one and quietly settles for an
analogy instead.

- **How X lays out and crops several images in one post.** X's own
  documentation covers upload limits and video aspect ratios and says nothing
  about the timeline grid. Measured instead, and expensively: a post with a
  wide tile and a square one side by side had the wide one centre-cropped to a
  tall slot, cutting the row labels off its left edge. Third-party guides say a
  single 16:9 image is shown whole and that a pair is cropped to roughly 7:8
  each. Both halves are now observed here rather than borrowed: the pair was
  cropped exactly that way on a published post, and the replacement — one
  1600×900 image — is drawn whole in the timeline and on the post page, nothing
  cut from any of the three tiles in it. `Docs/state-2026-08-16.md` finding 29
  has the order of events, which is the part worth reading: the post went out
  first and the reading happened after.
- **`ImageRenderer`'s default scale.** The property is documented; its default
  value is not stated anywhere Apple publishes. The 1.0 in the baseline checks
  was measured, and the comments say so.
- **Whether app-initiated reloads spend the widget budget more cheaply than
  system ones.** `SPEC` 2.3 marks this unverifiable and explains why. The
  cached WidgetKit page does list the cases that are exempt from the budget,
  which is narrower than the assumption but is a documented fact — see
  `SPEC` 2.3 before relying on either.
- **Writing into another bundle's container.** Permitted by ordinary file
  permissions, nowhere sanctioned by Apple. `SPEC` 2.2 records this as an
  accepted risk, not as a guarantee. Whether macOS 14's permission prompt
  applies to it is what `Docs/container-permission-test.md` exists to answer.
- **App Group refused under ad-hoc signing.** The sandbox pages describe group
  containers and the permission prompt; the `EPERM` this project measured is
  nowhere in them. `SPEC` 2.2 now says so at the place it is claimed.
- **A new inode on every `os.replace`.** Atomicity is documented as a POSIX
  requirement; the inode change is ours, from watching the number.
- **Creating a container from outside.** That the system creates it is
  documented. That doing it ourselves would make `containermanagerd` move it
  aside is one observation on one machine.
- **`chronod` holding a stale extension.** Apple does not document the daemon
  at all. Everything in `SPEC` 5.1 about it is measured here.
- **`SMAppService.mainApp.status` reports `notFound` before the first
  registration.** Apple's page for that case says "an error occurred and the
  framework couldn't find this service", and a probe inside the bundle says
  `before: notFound` → `register: succeeded` → `after: enabled`. Building on the
  documented meaning hid the switch in the state every user starts in. Measured
  on macOS 26.5; the documentation is not wrong about anything else here, and
  `openSystemSettingsLoginItems()` on the same page replaced a hand-written URL.
- **A process that is not the app cannot reload the widget.** `WidgetCenter`
  refuses an auxiliary executable shipped inside the app bundle —
  `ChronoCoreErrorDomain` code 27 from `getCurrentConfigurations`, and a
  `reloadAllTimelines()` that changes nothing. `ChronoCoreErrorDomain` appears
  in no Apple documentation at all. Measured on macOS 26.5 with a control, and
  `Tools/ccwidget-widgetkit-probe` re-establishes it on demand.
- **`statusLine` existing only in the terminal build.** The status line
  documentation never says it, and the whole audience limit in `SPEC` 14 rests
  on it.
- **Widget sizes on macOS.** Apple publishes size tables for iOS, iPadOS,
  visionOS and watchOS, and none for macOS. The numbers in `SPEC` 9 are
  measured through `TimelineProviderContext.displaySize`, with the date and
  system version beside them.
