import AppKit
import Carbon.HIToolbox
import Observation
import QuickPromptCore

/// App state and pipeline: trigger → capture → ActionRunner → paste (quick action) or copy (palette).
@MainActor @Observable
final class AppModel {
    enum Status {
        case idle, running, error
    }

    enum Output {
        /// Quick action: replace the selection.
        case paste
        /// Palette: leave the result in the clipboard.
        case copy
    }

    private(set) var status = Status.idle
    private(set) var accessibilityGranted = false
    private(set) var inputMonitoringGranted = false
    private(set) var doubleCopyActive = false
    private(set) var paletteHotKeyActive = false
    private(set) var secureInputEnabled = false
    private(set) var secureInputOwner: String?
    private(set) var launchAtLogin = false
    let store = PromptStore()
    let backendSettings = BackendSettings()

    var isRunning: Bool { status == .running }

    var statusSymbol: String {
        switch status {
        case .idle: "text.badge.checkmark"
        case .running: "ellipsis.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    @ObservationIgnored private let runner = ActionRunner()
    @ObservationIgnored private let hud = HUDController()
    @ObservationIgnored private let palette = PaletteController()
    @ObservationIgnored private let diagnostics = DiagnosticsWindowController()
    @ObservationIgnored private let settings = SettingsWindowController()
    @ObservationIgnored private var trigger: DoubleCopyTrigger?
    @ObservationIgnored private var paletteHotKey: GlobalHotKey?
    @ObservationIgnored private var monitorTimer: Timer?
    @ObservationIgnored private var currentTask: Task<Void, Never>?
    @ObservationIgnored private var currentRunID: UUID?
    @ObservationIgnored private var errorResetTask: Task<Void, Never>?

    private static let didShowDiagnosticsKey = "didShowDiagnosticsOnFirstLaunch"

    // MARK: - Lifecycle

    func start() {
        Log.app.info("quick-prompt started, API key present: \(self.backendSettings.hasAPIKey), Claude Code found: \(self.backendSettings.cliFound)")
        EditMenu.install()
        store.onSaveError = { [weak self] message in self?.hud.show("❌ \(message)", style: .error) }
        store.load()
        if store.loadError != nil {
            hud.show("❌ prompts.json is invalid (see Settings)", style: .error)
        }
        refreshStatus()

        if !accessibilityGranted {
            Permissions.requestAccessibility()
            if !UserDefaults.standard.bool(forKey: Self.didShowDiagnosticsKey) {
                UserDefaults.standard.set(true, forKey: Self.didShowDiagnosticsKey)
                showDiagnostics()
            }
        }
        if !inputMonitoringGranted {
            Permissions.requestInputMonitoring()
        }

        trigger = DoubleCopyTrigger { [weak self] in self?.handleDoubleCopy() }
        startTriggerIfPossible()

        let hotKey = GlobalHotKey(keyCode: kVK_ANSI_E, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            self?.openPalette()
        }
        paletteHotKey = hotKey
        paletteHotKeyActive = hotKey.register()
        if !paletteHotKeyActive {
            hud.show("⌃⌥⌘E is used by another app: palette shortcut unavailable", style: .warning)
        }

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Every 2 s: refresh permissions, start the listener once allowed, watch Secure Input.
    private func tick() {
        let wasSecure = secureInputEnabled
        refreshStatus()
        startTriggerIfPossible()

        if secureInputEnabled, !wasSecure {
            Log.system.warning("Secure Input enabled by \(self.secureInputOwner ?? "unknown", privacy: .public): double Cmd+C is blocked")
            hud.show("Secure Input is on: double ⌘C is blocked", style: .warning)
        } else if !secureInputEnabled, wasSecure {
            Log.system.info("Secure Input disabled")
        }
    }

    func refreshStatus() {
        accessibilityGranted = Permissions.accessibilityGranted
        inputMonitoringGranted = Permissions.inputMonitoringGranted
        doubleCopyActive = trigger?.isRunning ?? false
        secureInputEnabled = SecureInput.isEnabled
        secureInputOwner = secureInputEnabled ? SecureInput.ownerName() : nil
        launchAtLogin = LoginItem.isEnabled
    }

    private func startTriggerIfPossible() {
        guard let trigger, !trigger.isRunning, Permissions.inputMonitoringGranted else { return }
        doubleCopyActive = trigger.start()
    }

    // MARK: - Quick action

    var quickActionName: String? {
        store.library.quickAction?.name
    }

    /// Menu item: same as double Cmd+C, but the selection is captured first.
    func runQuickActionFromMenu() {
        Log.trigger.info("Trigger: menu")
        runQuickAction { () async -> CapturedText? in
            // Let the menu close so the source app gets its focus back.
            try? await Task.sleep(for: .milliseconds(150))
            return await SelectionCapture().capture()
        }
    }

    private func handleDoubleCopy() {
        let changeCount = NSPasteboard.general.changeCount
        runQuickAction { await ClipboardCapture(changeCountAtTrigger: changeCount).capture() }
    }

    private func runQuickAction(capture: @escaping @MainActor () async -> CapturedText?) {
        if store.loadError != nil {
            return fail("prompts.json is invalid (see Settings)")
        }
        guard let prompt = store.library.quickAction else {
            return fail("No quick action set (see Settings)")
        }
        guard prompt.isValid else {
            return fail("Quick action “\(prompt.name)” has no name or prompt")
        }
        run(TextAction(prompt: prompt), output: .paste, capture: capture)
    }

    // MARK: - Palette

    func openPalette() {
        Log.trigger.info("Trigger: palette shortcut")
        if palette.isVisible { return palette.close() }
        if store.loadError != nil {
            return fail("prompts.json is invalid (see Settings)")
        }
        let prompts = store.library.runnablePrompts
        guard !prompts.isEmpty else { return fail("No prompts (see Settings)") }
        if let message = preflightError() { return fail(message) }

        let quickActionID = store.library.quickActionID
        Task { [weak self] in
            guard let captured = await SelectionCapture().capture() else {
                Log.capture.warning("No text captured for the palette")
                self?.fail(ActionRunnerError.emptyInput.userMessage)
                return
            }
            Log.capture.info("Palette text via \(captured.method.rawValue, privacy: .public), length=\(captured.text.count)")
            self?.palette.show(prompts: prompts, quickActionID: quickActionID, text: captured.text) { prompt in
                Log.trigger.info("Palette: prompt chosen")
                self?.run(TextAction(prompt: prompt), output: .copy) { captured }
            }
        }
    }

    // MARK: - Pipeline

    func cancel() {
        guard currentTask != nil else { return }
        Log.app.info("Run cancelled by user")
        currentTask?.cancel()
        currentTask = nil
        currentRunID = nil
        Task { await runner.cancel() }
        status = .idle
        hud.show("Cancelled", style: .warning)
    }

    /// Starts a new run. A new run cancels the previous one.
    private func run(_ action: TextAction, output: Output, capture: @escaping @MainActor () async -> CapturedText?) {
        currentTask?.cancel()
        let runID = UUID()
        currentRunID = runID
        currentTask = Task { [weak self] in
            await self?.perform(action, output: output, runID: runID, capture: capture)
        }
    }

    /// System checks shared by every run. The backend is checked per prompt in `perform`.
    private func preflightError() -> String? {
        if !Permissions.accessibilityGranted { return "Accessibility permission missing (see Diagnostics)" }
        if SecureInput.isEnabled { return "Secure Input is on (\(SecureInput.ownerName() ?? "unknown app"))" }
        return nil
    }

    private func perform(
        _ action: TextAction,
        output: Output,
        runID: UUID,
        capture: @MainActor () async -> CapturedText?
    ) async {
        if let message = preflightError() ?? backendSettings.readinessError(for: action.backend) {
            return fail(message, runID: runID)
        }

        let captured = await capture()
        guard isCurrent(runID) else { return }
        guard let captured else {
            Log.capture.warning("No text captured")
            return fail(ActionRunnerError.emptyInput.userMessage, runID: runID)
        }
        Log.capture.info("Captured text via \(captured.method.rawValue, privacy: .public), length=\(captured.text.count)")

        errorResetTask?.cancel()
        status = .running
        hud.show("\(action.name)…", style: .progress)

        let start = ContinuousClock.now
        do {
            let backend = action.backend.rawValue
            let effort = action.effort?.rawValue ?? "none"
            Log.app.info("Run backend=\(backend, privacy: .public) model=\(action.model, privacy: .public) effort=\(effort, privacy: .public)")
            let provider = backendSettings.makeProvider(for: action.backend)
            let result = try await runner.run(action, input: captured.text, provider: provider)
            guard isCurrent(runID) else { return }
            Log.app.info("Run done in \(String(describing: ContinuousClock.now - start), privacy: .public), result length=\(result.count)")
            switch output {
            case .paste:
                await Paster.paste(result)
            case .copy:
                Paster.copy(result)
            }
            guard isCurrent(runID) else { return }
            status = .idle
            currentTask = nil
            hud.show(output == .paste ? "✅ Done" : "✅ Copied to clipboard", style: .success)
        } catch LLMError.cancelled {
            Log.app.info("Run cancelled")
        } catch let error as LLMError {
            fail(error.userMessage, runID: runID)
        } catch let error as ActionRunnerError {
            fail(error.userMessage, runID: runID)
        } catch {
            fail("Unexpected error", runID: runID)
        }
    }

    private func isCurrent(_ runID: UUID) -> Bool {
        currentRunID == runID && !Task.isCancelled
    }

    private func fail(_ message: String, runID: UUID) {
        guard isCurrent(runID) else { return }
        currentTask = nil
        fail(message)
    }

    /// Shows an error that is not tied to a run (or to the current one).
    private func fail(_ message: String) {
        Log.app.error("Failed: \(message, privacy: .public)")
        status = .error
        hud.show("❌ \(message)", style: .error)
        errorResetTask?.cancel()
        errorResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.status == .error else { return }
            self.status = .idle
        }
    }

    // MARK: - Menu actions

    func showDiagnostics() {
        diagnostics.show(model: self)
    }

    func showSettings() {
        settings.show(store: store, backend: backendSettings)
    }

    /// Resolved settings of the quick action, if any.
    var quickAction: TextAction? {
        store.library.quickAction.map(TextAction.init(prompt:))
    }

    /// Short summary for the menu, e.g. "Quick action: Haiku 4.5 · API key".
    var quickActionSummary: String? {
        quickAction.map { "Quick action: \(ClaudeModel.find($0.model).displayName) · \($0.backend.label)" }
    }

    /// Why the quick action's backend cannot run, if it cannot.
    var quickActionBackendError: String? {
        quickAction.flatMap { backendSettings.readinessError(for: $0.backend) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            Log.system.info("Launch at login: \(enabled)")
        } catch {
            Log.system.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            hud.show("❌ Could not change Launch at Login", style: .error)
        }
        launchAtLogin = LoginItem.isEnabled
    }
}
