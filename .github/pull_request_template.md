## What this changes and why

<!-- The diff says what. Spend these lines on why: the constraint, the
     failure, or the decision behind it. -->

## Checks

- [ ] `./Scripts/reinstall.sh` builds with no warnings
- [ ] `xcodebuild -project CCWidget.xcodeproj -scheme CCWidget test` passes
- [ ] `SPEC.md` updated if this contradicts it
- [ ] New user-facing strings are in the string catalogs; data uses `Text(verbatim:)`
- [ ] Nothing user-identifying logs as `.public`

## Verified how

<!-- Not "it should work". What did you run, and what did it print? -->
