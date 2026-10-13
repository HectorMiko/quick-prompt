import AppKit
import SwiftUI

/// Small floating message at the bottom of the active screen. Never takes focus.
@MainActor
final class HUDController {
    enum Style {
        case progress, success, warning, error

        var duration: Duration? {
            switch self {
            case .progress: nil
            case .success: .milliseconds(1500)
            case .warning, .error: .seconds(4)
            }
        }
    }

    private var panel: NSPanel?
    private let hostingView = NSHostingView(rootView: HUDView(message: "", style: .success))
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, style: Style) {
        hostingView.rootView = HUDView(message: message, style: style)
        let panel = panel ?? makePanel()
        self.panel = panel
        hostingView.layoutSubtreeIfNeeded()
        panel.setContentSize(hostingView.fittingSize)
        position(panel)
        panel.orderFrontRegardless()

        hideTask?.cancel()
        if let duration = style.duration {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hostingView
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 80))
    }
}

private struct HUDView: View {
    let message: String
    let style: HUDController.Style

    var body: some View {
        HStack(spacing: 8) {
            if style == .progress {
                ProgressView().controlSize(.small)
            }
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
        .padding(4)
    }
}
