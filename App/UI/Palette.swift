import AppKit
import Carbon.HIToolbox
import Observation
import QuickPromptCore
import SwiftUI

/// Prompt picker opened by ⌃⌥⌘E. Takes the keyboard without activating the app,
/// so the frontmost app keeps its selection.
@MainActor
final class PaletteController: NSObject, NSWindowDelegate {
    @MainActor @Observable
    final class Model {
        let prompts: [PromptItem]
        let quickActionID: String?
        let preview: String
        var selectedIndex = 0

        init(prompts: [PromptItem], quickActionID: String?, preview: String) {
            self.prompts = prompts
            self.quickActionID = quickActionID
            self.preview = preview
        }

        func moveSelection(by offset: Int) {
            guard !prompts.isEmpty else { return }
            selectedIndex = (selectedIndex + offset + prompts.count) % prompts.count
        }
    }

    private var panel: PalettePanel?
    private var model: Model?
    private var keyMonitor: Any?
    private var onChoose: ((PromptItem) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(prompts: [PromptItem], quickActionID: String?, text: String, onChoose: @escaping (PromptItem) -> Void) {
        let model = Model(prompts: prompts, quickActionID: quickActionID, preview: Self.preview(of: text))
        self.model = model
        self.onChoose = onChoose

        let panel = panel ?? makePanel()
        self.panel = panel
        let hostingView = NSHostingView(rootView: PaletteView(model: model) { [weak self] index in
            self?.choose(index)
        })
        panel.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        panel.setContentSize(hostingView.fittingSize)
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        Log.app.info("Palette opened with \(prompts.count) prompts")
    }

    func close() {
        removeKeyMonitor()
        panel?.orderOut(nil)
        model = nil
        onChoose = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func choose(_ index: Int) {
        guard let model, model.prompts.indices.contains(index) else { return }
        let prompt = model.prompts[index]
        let onChoose = onChoose
        close()
        onChoose?(prompt)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let model = self.model else { return event }
            switch Int(event.keyCode) {
            case kVK_UpArrow: model.moveSelection(by: -1)
            case kVK_DownArrow: model.moveSelection(by: 1)
            case kVK_Return, kVK_ANSI_KeypadEnter: self.choose(model.selectedIndex)
            case kVK_Escape: self.close()
            default: return event
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func makePanel() -> PalettePanel {
        let panel = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY + frame.height / 6 - size.height / 2))
    }

    /// First line of the captured text, shortened.
    static func preview(of text: String, limit: Int = 80) -> String {
        let firstLine = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        let isShortened = firstLine.count > limit || text.trimmingCharacters(in: .whitespacesAndNewlines).contains("\n")
        return String(firstLine.prefix(limit)) + (isShortened ? "…" : "")
    }
}

/// Borderless panels refuse key status by default.
final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct PaletteView: View {
    let model: PaletteController.Model
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.preview)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            ForEach(Array(model.prompts.enumerated()), id: \.element.id) { index, prompt in
                HStack {
                    Text(prompt.name).lineLimit(1)
                    Spacer()
                    if prompt.id == model.quickActionID {
                        Text("⌘C ⌘C").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    index == model.selectedIndex ? Color.accentColor.opacity(0.25) : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
                .onTapGesture { onChoose(index) }
            }
            Text("↑↓ to select · ↩ to run (result is copied) · esc to close")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(width: 460, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
