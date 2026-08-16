import Foundation
import Testing

/// Soft parsing has to be loud. Section 6.1.
///
/// This is the rule three separate defects hid behind — a fractional
/// percentage, an unreachable App Group, a doubled sandbox path — and each
/// time the symptom was the same: no data, no reason, nothing in the log. It
/// is also the rule that had no check at all. Every one of these asserts what
/// the parser *says*, not only what it returns.
@Suite("Loud soft parsing")
struct DiagnosticsTests {

    private func parse(_ json: String) throws -> Snapshot {
        try SnapshotStore.makeDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }

    /// Enough to be a snapshot and nothing more. Everything optional is
    /// absent, which is the ordinary state in the first seconds of a session.
    private let minimal = #"{"schemaVersion":1,"capturedAt":1700000000}"#

    // MARK: The exception to the rule

    /// The single exception in section 6.1: a field that is not there is not
    /// a problem. `rate_limits` genuinely does not exist until the model has
    /// answered once, and shouting about it every second would teach the
    /// reader to ignore the diagnostics entirely.
    @Test("A field that is absent says nothing")
    func absentFieldsAreSilent() throws {
        let snapshot = try parse(minimal)
        #expect(snapshot.diagnostics.isEmpty,
                "got \(snapshot.diagnostics.map(\.summary))")
        #expect(snapshot.limits.fiveHour == nil)
        #expect(snapshot.limits.sevenDay == nil)
    }

    /// The other half of the same exception. An explicit `null` is the source
    /// saying "I have no value", which is information, not corruption.
    @Test("An explicit null says nothing either")
    func nullFieldsAreSilent() throws {
        let snapshot = try parse("""
        {"schemaVersion":1,"capturedAt":1700000000,"sessionId":null,"model":null,"limits":null}
        """)
        #expect(snapshot.diagnostics.isEmpty,
                "got \(snapshot.diagnostics.map(\.summary))")
        #expect(snapshot.sessionId == nil)
    }

    /// And the rule itself. A field that is present and does not parse is the
    /// case worth hearing about: something upstream changed shape, and the
    /// dash the widget draws is a consequence rather than a state.
    @Test("A field that is present and broken is reported")
    func brokenFieldIsReported() throws {
        let snapshot = try parse("""
        {"schemaVersion":1,"capturedAt":1700000000,"sessionId":42}
        """)
        #expect(snapshot.sessionId == nil, "the field is dropped")
        #expect(snapshot.diagnostics.count == 1,
                "got \(snapshot.diagnostics.map(\.summary))")

        let issue = try #require(snapshot.diagnostics.first)
        #expect(issue.field == "sessionId", "the report names the field")
        #expect(issue.rawValue == "42", "and carries what was actually there")
        #expect(!issue.reason.isEmpty, "and why it could not be read")
    }

    /// One broken field does not take the snapshot down, and does not take
    /// its neighbours with it.
    @Test("A broken field costs only itself")
    func oneBrokenFieldDoesNotSpread() throws {
        let snapshot = try parse("""
        {"schemaVersion":1,"capturedAt":1700000000,"sessionId":42,
         "claudeCodeVersion":"2.1.220",
         "limits":{"sevenDay":{"usedPercentage":9,"resetsAt":1700100000}}}
        """)
        #expect(snapshot.claudeCodeVersion == "2.1.220", "the good neighbour survives")
        #expect(snapshot.limits.sevenDay?.usedPercentage == 9, "and so does the window")
        #expect(snapshot.diagnostics.map(\.field) == ["sessionId"])
    }

    /// A window that is there and unreadable is reported under its own path,
    /// not under `limits` — the log has to say which of the two it was.
    @Test("A broken window is reported by its own path")
    func brokenWindowNamesItself() throws {
        let snapshot = try parse("""
        {"schemaVersion":1,"capturedAt":1700000000,
         "limits":{"fiveHour":{"usedPercentage":21},
                   "sevenDay":{"usedPercentage":9,"resetsAt":1700100000}}}
        """)
        #expect(snapshot.limits.fiveHour == nil, "the broken window is dropped")
        #expect(snapshot.limits.sevenDay != nil, "the intact one is kept")
        #expect(snapshot.diagnostics.map(\.field) == ["limits.fiveHour"],
                "got \(snapshot.diagnostics.map(\.summary))")
    }

    // MARK: The fractional percentage

    /// The defect that started the rule. A live snapshot carried
    /// `"used_percentage": 28.000000000000004`; strict decoding threw, the
    /// soft path swallowed it, and an entire limit window vanished with no
    /// explanation anywhere. It was fixed in two places and left a comment
    /// behind instead of a check.
    @Test("A fractional percentage is rounded, not dropped",
          arguments: [("28.000000000000004", 28), ("28", 28), ("27.6", 28), ("0.4", 0), ("99.5", 100)])
    func fractionalPercentageSurvives(literal: String, expected: Int) throws {
        let snapshot = try parse("""
        {"schemaVersion":1,"capturedAt":1700000000,
         "limits":{"sevenDay":{"usedPercentage":\(literal),"resetsAt":1700100000}}}
        """)
        #expect(snapshot.limits.sevenDay?.usedPercentage == expected,
                "\(literal) → \(String(describing: snapshot.limits.sevenDay?.usedPercentage))")
        #expect(snapshot.diagnostics.isEmpty,
                "a number the source is entitled to send is not a defect: \(snapshot.diagnostics.map(\.summary))")
    }

    /// A percentage that is not a number at all is a different matter, and
    /// has to be heard.
    @Test("A percentage that is not a number is reported")
    func nonNumericPercentageIsReported() throws {
        let snapshot = try parse("""
        {"schemaVersion":1,"capturedAt":1700000000,
         "limits":{"sevenDay":{"usedPercentage":"nine","resetsAt":1700100000}}}
        """)
        #expect(snapshot.limits.sevenDay == nil)
        #expect(snapshot.diagnostics.map(\.field) == ["limits.sevenDay"])
    }

    // MARK: What the log is given to look at

    /// `JSONValue` exists for one reason: to put the offending value in the
    /// log next to the field name. A reason without a value sends the reader
    /// back to the file to guess which of two plausible shapes arrived.
    ///
    /// Each case of it is produced here, which is also what keeps the enum
    /// honest — see the rule about enum cases in CLAUDE.md.
    @Test("The raw value is rendered in every shape JSON has",
          arguments: [
            ("42", "42"),                       // number
            ("true", "true"),                   // bool
            ("[1, 2]", "[1, 2]"),               // array
            ("[null]", "[null]"),               // array containing null
            (#"{"a":1}"#, "{a: 1}"),            // object
          ])
    func rawValueShapes(literal: String, rendered: String) throws {
        // sessionId is declared String, so anything else fails and is recorded
        // with its raw value intact.
        let snapshot = try parse("""
        {"schemaVersion":1,"capturedAt":1700000000,"sessionId":\(literal)}
        """)
        let issue = try #require(snapshot.diagnostics.first,
                                 "nothing was recorded for \(literal)")
        #expect(issue.rawValue == rendered, "\(literal) → \(issue.rawValue ?? "nil")")
    }

    /// The six shapes by name. The check above proves each one reaches the
    /// log with the right rendering; this one proves each is a case somebody
    /// asks for, which is the rule about enum cases in CLAUDE.md applied to a
    /// type whose cases are otherwise only ever produced by accident.
    @Test("Every JSON shape decodes to its own case")
    func jsonValueCasesAreDistinct() throws {
        func value(_ literal: String) throws -> JSONValue {
            try JSONDecoder().decode(JSONValue.self, from: Data(literal.utf8))
        }

        guard case .null = try value("null") else {
            Issue.record("null did not decode to .null"); return
        }
        guard case .bool(let flag) = try value("true") else {
            Issue.record("true did not decode to .bool"); return
        }
        #expect(flag)
        guard case .number(let number) = try value("42.5") else {
            Issue.record("42.5 did not decode to .number"); return
        }
        #expect(number == 42.5)
        guard case .string(let text) = try value("\"hi\"") else {
            Issue.record("a string did not decode to .string"); return
        }
        #expect(text == "hi")
        guard case .array(let items) = try value("[1, null]") else {
            Issue.record("an array did not decode to .array"); return
        }
        #expect(items.count == 2)
        guard case .object(let fields) = try value(#"{"a":1}"#) else {
            Issue.record("an object did not decode to .object"); return
        }
        #expect(fields.keys.sorted() == ["a"])
    }

    /// The string shape, from the other direction: a field declared as an
    /// object that receives a string.
    @Test("A string in the wrong place is rendered as a string")
    func rawValueString() throws {
        let snapshot = try parse("""
        {"schemaVersion":1,"capturedAt":1700000000,"model":"opus"}
        """)
        let issue = try #require(snapshot.diagnostics.first)
        #expect(issue.field == "model")
        #expect(issue.rawValue == "\"opus\"", "got \(issue.rawValue ?? "nil")")
    }

    /// A raw value long enough to fill the log is truncated. The log exists to
    /// be read; a megabyte of pasted JSON in it is the same as nothing.
    @Test("A very long raw value is truncated")
    func rawValueTruncated() throws {
        let long = (0..<200).map { "\"item\($0)\"" }.joined(separator: ",")
        let snapshot = try parse("""
        {"schemaVersion":1,"capturedAt":1700000000,"sessionId":[\(long)]}
        """)
        let issue = try #require(snapshot.diagnostics.first)
        let raw = try #require(issue.rawValue)
        #expect(raw.count <= 201, "\(raw.count) characters")
        #expect(raw.hasSuffix("…"), "and it says it was cut")
    }

    /// The summary is what the window shows under Details. It has to name all
    /// three things, or it sends the reader to the log for the rest.
    @Test("The summary carries the field, the value and the reason")
    func summaryIsSelfContained() throws {
        let snapshot = try parse("""
        {"schemaVersion":1,"capturedAt":1700000000,"sessionId":42}
        """)
        let summary = try #require(snapshot.diagnostics.first?.summary)
        #expect(summary.contains("sessionId"))
        #expect(summary.contains("42"))
        #expect(summary.count > "sessionId = 42 — ".count, "the reason is not empty: \(summary)")
    }

    // MARK: Required fields

    /// Two fields are not soft, and must not become so. A snapshot without a
    /// schema version cannot be checked for compatibility; one without a
    /// capture moment cannot be aged, and an ageless snapshot would be drawn
    /// as fresh forever.
    @Test("A snapshot without its two required fields does not parse",
          arguments: [
            #"{"capturedAt":1700000000}"#,
            #"{"schemaVersion":1}"#,
            #"{}"#,
          ])
    func requiredFieldsAreRequired(json: String) {
        #expect(throws: (any Error).self) { try parse(json) }
    }

    // MARK: The other half of "loud"

    /// Until this check, every assertion about the rule looked only at the
    /// value coming back nil — the quiet half. The message actually reaching
    /// the log is the half that matters when someone is looking at a widget
    /// showing a dash and wondering why.
    @Test("A dropped field reaches the log, not only the diagnostics")
    func droppedFieldIsLogged() throws {
        var parsed: Snapshot?
        let messages = try logMessages(matching: "soft parse dropped field") {
            parsed = try? self.parse("""
            {"schemaVersion":1,"capturedAt":1700000000,"sessionId":42}
            """)
        }
        #expect(parsed?.diagnostics.count == 1)
        #expect(!messages.isEmpty, "nothing was written to the log")
        #expect(messages.contains { $0.contains("sessionId") },
                "the log names the field: \(messages)")
    }
}

/// The history is read on every timeline build, and a single truncated last
/// line — the exporter was interrupted mid-append — must cost that line and
/// nothing else.
@Suite("History")
struct HistoryTests {

    private func store(_ lines: [String]) -> HistoryStore {
        let dir = sandbox()
        let url = dir.appending(path: "history.jsonl")
        try! lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return HistoryStore(url: url)
    }

    private func line(_ t: Int, _ used: Int) -> String {
        #"{"t":\#(t),"sevenDay":\#(used),"resetsAt":9}"#
    }

    @Test("A broken line is skipped and the rest survive")
    func brokenLineIsSkipped() {
        let entries = store([
            line(1, 1),
            "{ this is not json",
            line(2, 2),
        ]).load()
        #expect(entries.count == 2, "got \(entries.count)")
        #expect(entries.map(\.sevenDayUsed) == [1, 2])
    }

    /// The exporter appends, so an interrupted write leaves half a line at the
    /// end. That is the common case, not a hypothetical one.
    @Test("A truncated last line costs only itself")
    func truncatedTailIsSkipped() {
        let entries = store([line(1, 1), line(2, 2), #"{"t":3,"sevenDay":"#]).load()
        #expect(entries.count == 2)
    }

    @Test("Skipped lines reach the log")
    func skippedLinesAreLogged() throws {
        let s = store([line(1, 1), "{ broken", line(2, 2)])
        var count = 0
        let messages = try logMessages(matching: "history line dropped") {
            count = s.load().count
        }
        #expect(count == 2)
        #expect(!messages.isEmpty, "a dropped line was not logged")
    }

    @Test("Entries come back in time order however they were written")
    func entriesAreSorted() {
        let entries = store([line(30, 3), line(10, 1), line(20, 2)]).load()
        #expect(entries.map(\.sevenDayUsed) == [1, 2, 3])
    }

    @Test("A history that is not there is empty, not an error")
    func missingFileIsEmpty() {
        #expect(HistoryStore(url: sandbox().appending(path: "nope.jsonl")).load().isEmpty)
    }

    // MARK: Truncation

    /// Section 7: at most 2000 lines, and past that the last 1000 are kept.
    /// Neither number was asserted anywhere — the only check that called
    /// `truncateIfNeeded` was about symlinks.
    @Test("Past the ceiling, the last thousand lines are kept")
    func truncationKeepsTheTail() throws {
        let s = store((0..<2500).map { line($0, $0 % 100) })
        let removed = s.truncateIfNeeded()

        #expect(removed == 1500, "removed \(removed)")
        let kept = s.load()
        #expect(kept.count == HistoryStore.keepLines, "kept \(kept.count)")
        #expect(kept.first?.time == Date(timeIntervalSince1970: 1500),
                "the tail is kept, not the head")
        #expect(kept.last?.time == Date(timeIntervalSince1970: 2499))
    }

    @Test("Below the ceiling nothing is touched",
          arguments: [1, 999, 1999, HistoryStore.maxLines])
    func truncationLeavesShortHistoriesAlone(count: Int) {
        let s = store((0..<count).map { line($0, 1) })
        #expect(s.truncateIfNeeded() == 0, "\(count) lines")
        #expect(s.load().count == count)
    }

    // MARK: What the log may say out loud

    /// The reason a field was dropped is built by interpolating an arbitrary
    /// error, so it goes to the log private. What stays public is the
    /// classification, and a classification is only useful if it is a closed
    /// vocabulary — every one of these has to be produced, or a case nobody
    /// expects is wrong for ever.
    @Test("The public half of a parse failure is a fixed vocabulary",
          arguments: [("expected Int, found a string", "typeMismatch"),
                      ("no value for Int", "valueNotFound"),
                      ("missing key resets_at", "keyNotFound"),
                      ("The data isn\u{2019}t in the correct format.", "dataCorrupted"),
                      ("", "unknown")])
    func theKindIsAClosedVocabulary(reason: String, kind: String) {
        #expect(DiagnosticsCollector.kind(of: reason) == kind, "\(reason)")
    }

    /// And the thing the vocabulary exists for: a value out of somebody's
    /// snapshot must not reach a public field through it.
    @Test("A value from the data cannot arrive in the public field")
    func theKindCarriesNoData() {
        let secret = "/Users/someone/Documents/secret-client"
        #expect(!DiagnosticsCollector.kind(of: "expected Int, found \(secret)").contains(secret))
        #expect(!DiagnosticsCollector.kind(of: secret).contains("secret"))
    }
}
