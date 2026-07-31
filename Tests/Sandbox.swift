import Foundation

// Everything the checks touch lives inside a stand-in home directory: the root
// arrives as a parameter (section 5.2), so the real ~/.claude takes no part and
// cannot be harmed. This is exactly the isolation that was missing when the
// installer worked out the home directory by itself and overwrote a live
// config.
//
// Each call makes its own directory under a fresh UUID, which is also what lets
// the suites run in parallel: no two of them ever look at the same file.

func sandbox() -> URL {
    let root = URL(filePath: NSTemporaryDirectory())
        .appending(path: "ccwidget-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// Stands in for the directory the system creates when the widget extension
/// first runs. Installing refuses without it, so most checks need it present.
func makeContainer(in home: URL) {
    try! FileManager.default.createDirectory(
        at: SnapshotStore.widgetContainerURL(home: home)
            .appending(path: "Data/Library/Application Support"),
        withIntermediateDirectories: true
    )
}

/// The smallest template the installer will accept: a shebang to rewrite and a
/// placeholder to substitute.
func makeTemplate(in root: URL) -> URL {
    let url = root.appending(path: "ccwidget-export.py.template")
    try! "#!/usr/bin/env python3\nGROUP_DIR = \"__GROUP_DIR__\"\n"
        .write(to: url, atomically: true, encoding: .utf8)
    return url
}

func installer(home: URL, template: URL) -> Installer {
    Installer(
        home: home,
        exchangeDirectory: SnapshotStore.exchangeURL(home: home),
        templateURL: template
    )
}

func isSymlink(_ url: URL) -> Bool {
    let type = try? FileManager.default.attributesOfItem(
        atPath: url.path(percentEncoded: false))[.type] as? FileAttributeType
    return type == .typeSymbolicLink
}

func settings(_ home: URL) -> String {
    (try? String(contentsOf: home.appending(path: ".claude/settings.json"), encoding: .utf8)) ?? ""
}

func write(_ text: String, to home: URL) {
    let dir = home.appending(path: ".claude")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try! text.write(to: dir.appending(path: "settings.json"), atomically: true, encoding: .utf8)
}

func posixMode(of url: URL) -> Int {
    let value = try! FileManager.default.attributesOfItem(
        atPath: url.path(percentEncoded: false))[.posixPermissions] as! NSNumber
    return value.intValue
}

func parseJSON(_ text: String) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
}

// Reaching into the outcome as an optional keeps each check a statement about
// the property — "the edit was surgical" — instead of a `guard` that skips the
// check entirely when it fails.
extension SettingsEditor.Outcome {
    var surgicalText: String? {
        if case .surgical(let text) = self { return text }
        return nil
    }

    var rewrittenText: String? {
        if case .rewritten(let text) = self { return text }
        return nil
    }
}
