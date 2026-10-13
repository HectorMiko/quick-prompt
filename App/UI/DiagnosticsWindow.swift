import AppKit
import QuickPromptCore
import SwiftUI

@MainActor
final class DiagnosticsWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        model.refreshStatus()
        let window = window ?? makeWindow(model: model)
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(model: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "quick-prompt Diagnostics"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DiagnosticsView(model: model))
        window.center()
        return window
    }
}

private struct DiagnosticsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Permissions") {
                row(
                    "Accessibility",
                    ok: model.accessibilityGranted,
                    detail: "Needed to read the selection and paste.",
                    action: ("Open System Settings", Permissions.openAccessibilitySettings)
                )
                row(
                    "Input Monitoring",
                    ok: model.inputMonitoringGranted,
                    detail: "Needed for the double ⌘C shortcut.",
                    action: ("Open System Settings", Permissions.openInputMonitoringSettings)
                )
            }
            Section("Status") {
                row("Double ⌘C listener", ok: model.doubleCopyActive, detail: model.doubleCopyActive ? "Active" : "Inactive")
                row(
                    "Secure Input",
                    ok: !model.secureInputEnabled,
                    detail: model.secureInputEnabled
                        ? "On (\(model.secureInputOwner ?? "unknown app")): keyboard shortcuts are blocked."
                        : "Off"
                )
                row(
                    "Palette shortcut ⌃⌥⌘E",
                    ok: model.paletteHotKeyActive,
                    detail: model.paletteHotKeyActive ? "Registered" : "Unavailable: used by another app."
                )
                row(
                    "Prompts",
                    ok: model.store.loadError == nil,
                    detail: model.store.loadError.map { "prompts.json is invalid: \($0)" }
                        ?? "\(model.store.library.prompts.count) prompts in \(model.store.fileURL.path)"
                )
                row(
                    "Anthropic API",
                    ok: model.backendSettings.hasAPIKey,
                    detail: model.backendSettings.apiKeySuffix.map { "Key sk-ant-…\($0)" } ?? "No API key (see Settings)"
                )
                row(
                    "Claude Code",
                    ok: model.backendSettings.cliFound,
                    detail: model.backendSettings.cliFound
                        ? "Found at \(model.backendSettings.cliPath)"
                        : "Not found at \(model.backendSettings.cliPath)"
                )
                row("Quick action", ok: model.quickActionBackendError == nil, detail: quickActionDetail)
            }
            Section("Logs") {
                Text("Run `make logs` in the project folder, or filter Console.app on subsystem \(Log.subsystem).")
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var quickActionDetail: String {
        guard let prompt = model.store.library.quickAction else { return "No quick action" }
        let action = TextAction(prompt: prompt)
        let effort = action.effort.map { ", effort \($0.rawValue)" } ?? ""
        return "\(action.backend.label), \(ClaudeModel.find(action.model).displayName)\(effort), timeout \(Int(action.timeout)) s, max tokens \(action.maxTokens)"
    }

    private func row(
        _ title: String,
        ok: Bool,
        detail: String,
        action: (String, () -> Void)? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let action, !ok {
                Button(action.0, action: action.1)
            }
        }
    }
}
