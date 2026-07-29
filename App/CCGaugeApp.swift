import SwiftUI

@main
struct CCGaugeApp: App {
    var body: some Scene {
        Window("Gauge for Claude Code", id: "main") {
            StatusView()
        }
        .windowResizability(.contentSize)
    }
}
