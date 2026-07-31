import SwiftUI
import WidgetKit

/// The first-run screen. Section 11: three steps, hand-held.
///
/// The product's weakest point is that the widget does nothing until the user
/// adds a line to the Claude Code config. This screen exists precisely so
/// that step cannot be missed and cannot be done wrong.
struct OnboardingView: View {
    @State private var step: OnboardingStep = .checkClaudeCode
    @State private var failure: String?
    @State private var backupPath: String?
    @State private var wasSurgical = true
    private let installer = Installer.live()
    @State private var showsManual = false
    @State private var firstSnapshot: Snapshot?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            switch step {
            case .checkClaudeCode: checkStep
            case .install: installStep
            case .waitingForData: waitingStep
            case .ready: readyStep
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: advanceFromCheck)
        .onDisappear { pollTask?.cancel() }
        .sheet(isPresented: $showsManual) { manualSheet }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Usage Widget for Claude Code")
                .font(.title2.weight(.semibold))
            Text("Subscription limits on your desktop.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Step 1 — detection

    @ViewBuilder
    private var checkStep: some View {
        if installer.isClaudeCodePresent {
            Label("Claude Code detected.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button("Continue") { step = .install }
                .keyboardShortcut(.defaultAction)
        } else {
            Label("Claude Code was not found.", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
            Text("This widget reads the Claude Code status line, so the terminal version has to be installed and used at least once.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Link("Install Claude Code", destination: URL(string: "https://claude.com/claude-code")!)
                Button("Check again") { advanceFromCheck() }
            }
        }
    }

    private func advanceFromCheck() {
        step = step.afterCheckingClaudeCode(present: installer.isClaudeCodePresent)
    }

    // MARK: Step 2 — installation

    @ViewBuilder
    private var installStep: some View {
        // Section 2.2: with no extension container there is no path to
        // substitute.
        if !installer.widgetContainerExists {
            Label("Add the widget to your desktop first.", systemImage: "square.grid.2x2")
                .font(.callout.weight(.medium))
            Text("The exchange directory is created by the system when the widget first runs. Right-click the desktop, choose Edit Widgets, add Usage Widget for Claude Code, then come back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Check again") { failure = nil }
        } else {
            existingStatusLineWarning
            preflightNotes

            VStack(alignment: .leading, spacing: 6) {
                Text("Setup writes the exporter to ~/.claude/ and adds one key to settings.json. Only that key changes — your formatting and key order are kept.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("A copy is saved as \(installer.backupNamePattern) next to it first.")
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button("Set up automatically") { runInstall() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(installer.preflight().interpreter == nil)
                Button("Show manual instructions") { showsManual = true }
            }
        }
    }

    /// Section 11: warn before writing, not report afterwards.
    @ViewBuilder
    private var preflightNotes: some View {
        let check = installer.preflight()
        VStack(alignment: .leading, spacing: 6) {
            if let target = check.settingsLinkTarget {
                if check.canPreserveLink {
                    Label("settings.json is a symlink. Setup writes through it, so the link stays intact.", systemImage: "link")
                        .foregroundStyle(.secondary)
                } else {
                    Label("settings.json is a symlink whose target cannot be written. Setup would replace the link with a regular file.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Text(verbatim: target.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if check.interpreter == nil {
                Label("No working python3 was found. Install the Xcode Command Line Tools with: xcode-select --install", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if let interpreter = check.interpreter {
                Text("Exporter will run under \(interpreter.path(percentEncoded: false))")
                    .foregroundStyle(.tertiary)
            }
            if !check.settingsWritable {
                Label("settings.json is not writable.", systemImage: "lock.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// An existing key must never be overwritten silently — section 11.
    @ViewBuilder
    private var existingStatusLineWarning: some View {
        if case .foreign(let command) = installer.statusLineState() {
            VStack(alignment: .leading, spacing: 4) {
                Label("Another status line is already configured.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(command)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("Setup will replace it. The backup lets you put it back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func runInstall() {
        failure = nil
        do {
            let report = try installer.install()
            backupPath = report.backup?.lastPathComponent
            wasSurgical = report.editWasSurgical
            step = step.afterInstalling()
            startPolling()
        } catch {
            failure = error.localizedDescription
        }
    }

    // MARK: Step 3 — waiting

    private var waitingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Launch Claude Code and send any message.")
                    .font(.callout)
            }
            Text("The status line runs on every redraw, so the first numbers appear within seconds of the model replying.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let backupPath {
                Text("Settings backed up as \(backupPath)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if !wasSurgical {
                // Section 11: if the surgical edit failed, say so.
                Label("settings.json had to be rewritten, so key order and indentation changed. The backup has the original.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                if let snapshot = try? SnapshotStore.default().load() {
                    firstSnapshot = snapshot
                    step = step.afterFirstSnapshot()
                    WidgetCenter.shared.reloadAllTimelines()
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Done

    @ViewBuilder
    private var readyStep: some View {
        Label("Live data is coming in.", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)

        if let snapshot = firstSnapshot {
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    if let week = snapshot.limits.sevenDay {
                        LabeledContent("Week used", value: CCWidgetFormat.percent(week.usedPercentage))
                    }
                    if let used = snapshot.context?.usedPercentage {
                        LabeledContent("Context used", value: CCWidgetFormat.percent(used))
                    }
                }
                .font(.callout.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        Text("If the widget is not on your desktop yet, right-click the desktop and choose Edit Widgets.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Manual instructions

    private var manualSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual setup")
                .font(.headline)
            ScrollView {
                Text(installer.manualInstructions())
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 240)
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(installer.manualInstructions(), forType: .string)
                }
                Spacer()
                Button("Done") { showsManual = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
