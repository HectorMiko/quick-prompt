import AppKit
import SwiftUI

struct MenuBarIcon: View {
    let model: AppModel

    var body: some View {
        Image(systemName: model.statusSymbol)
    }
}

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Button(model.quickActionName.map { "Run Quick Action: \($0)" } ?? "Run Quick Action") {
            model.runQuickActionFromMenu()
        }
        if let summary = model.quickActionSummary {
            Text(summary)
        }
        Button("Open Palette…") { model.openPalette() }
            .keyboardShortcut("e", modifiers: [.control, .option, .command])
        if model.isRunning {
            Button("Cancel") { model.cancel() }
        }

        Divider()

        if !model.accessibilityGranted {
            Button("⚠️ Accessibility permission missing…") { model.showDiagnostics() }
        }
        if !model.inputMonitoringGranted {
            Button("⚠️ Input Monitoring permission missing…") { model.showDiagnostics() }
        }
        if let message = model.quickActionBackendError {
            Button("⚠️ \(message)…") { model.showSettings() }
        }
        Button("Settings…") { model.showSettings() }
            .keyboardShortcut(",")
        Button("Diagnostics…") { model.showDiagnostics() }
        Toggle("Launch at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))

        Divider()

        Button("Quit quick-prompt") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
