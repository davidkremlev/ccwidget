import Foundation
import Testing

/// The editor writes into a file the user owns and did not create for us.
/// Every check here is about leaving the rest of that file exactly as it was:
/// key order, indentation, and the keys we have no business touching.
@Suite("Settings editor")
struct SettingsEditorTests {

    private let value: [String: Any] = ["type": "command", "command": "/tmp/x.py", "padding": 0]

    @Test("Adding a key that is not there yet")
    func addsNewKey() {
        let original = """
        {
          "theme": "dark",
          "permissions": {
            "defaultMode": "auto"
          },
          "language": "Russian"
        }
        """
        let edited = SettingsEditor.setting("statusLine", to: value, in: original).surgicalText
        #expect(edited != nil, "a new key is added surgically")
        guard let edited else { return }

        #expect(
            edited.range(of: "\"theme\"")!.lowerBound < edited.range(of: "\"permissions\"")!.lowerBound
            && edited.range(of: "\"permissions\"")!.lowerBound < edited.range(of: "\"language\"")!.lowerBound,
            "the order of the existing keys survives")
        #expect(edited.contains("  \"language\": \"Russian\""),
                "the existing lines are untouched")
        #expect(edited.contains("\n  \"statusLine\": {"),
                "the indentation is picked up from the file")
        #expect(parseJSON(edited) != nil, "the result parses")
    }

    @Test("Replacing a key that is already there")
    func replacesExistingKey() {
        let original = """
        {
          "theme": "dark",
          "statusLine": {
            "type": "command",
            "command": "/old/script.sh",
            "padding": 4
          },
          "language": "Russian"
        }
        """
        let edited = SettingsEditor.setting(
            "statusLine", to: ["type": "command", "command": "/new.py", "padding": 0],
            in: original).surgicalText
        #expect(edited != nil, "an existing key is replaced surgically")
        guard let edited else { return }

        #expect(!edited.contains("/old/script.sh"), "the old command is gone")
        #expect(edited.contains("/new.py"), "the new command is there")
        #expect(edited.contains("\"theme\": \"dark\"") && edited.contains("\"language\": \"Russian\""),
                "the neighbouring keys are intact")
        #expect(
            edited.range(of: "\"theme\"")!.lowerBound < edited.range(of: "\"statusLine\"")!.lowerBound
            && edited.range(of: "\"statusLine\"")!.lowerBound < edited.range(of: "\"language\"")!.lowerBound,
            "the key stays where it was")
    }

    @Test("A key of the same name further down is left alone")
    func ignoresNestedKeyOfTheSameName() {
        let original = """
        {
          "nested": {
            "statusLine": "leave me alone"
          },
          "theme": "dark"
        }
        """
        let edited = SettingsEditor.setting("statusLine", to: value, in: original).surgicalText
        #expect(edited?.contains("\"leave me alone\"") == true,
                "a nested key of the same name is not confused with the top one")
        guard let edited else { return }

        let parsed = parseJSON(edited)
        #expect(parsed?["statusLine"] is [String: Any], "the top-level key was added")
        #expect((parsed?["nested"] as? [String: Any])?["statusLine"] as? String == "leave me alone",
                "the nested one is still a string")
    }

    @Test("An empty object")
    func fillsEmptyObject() {
        let edited = SettingsEditor.setting("statusLine", to: value, in: "{}").surgicalText
        #expect(edited?.contains("\"statusLine\"") == true, "an empty object gets filled in")
        #expect(edited.flatMap(parseJSON) != nil, "an empty object stays valid")
    }

    @Test("Tabs instead of spaces")
    func keepsTabIndentation() {
        let original = "{\n\t\"theme\": \"dark\"\n}"
        let edited = SettingsEditor.setting("statusLine", to: value, in: original).surgicalText
        #expect(edited?.contains("\n\t\"statusLine\"") == true, "tab indentation survives")
    }

    @Test("Broken JSON falls back to a rewrite")
    func rewritesBrokenFile() {
        // Nothing can be edited in place inside a file that does not parse, so
        // the only honest move is a rewrite — and the caller has to be told,
        // because the user's formatting is lost either way.
        let text = SettingsEditor.setting("statusLine", to: value, in: "{ not json at all").rewrittenText
        #expect(text?.contains("\"statusLine\"") == true, "a broken file falls back to a rewrite")
    }
}
