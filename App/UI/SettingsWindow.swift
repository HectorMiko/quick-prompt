import AppKit
import QuickPromptCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(store: PromptStore, backend: BackendSettings) {
        let window = window ?? makeWindow(store: store, backend: backend)
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(store: PromptStore, backend: BackendSettings) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "quick-prompt Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 640, height: 400)
        window.contentView = NSHostingView(rootView: SettingsRoot(store: store, backend: backend))
        window.center()
        return window
    }
}

private struct SettingsRoot: View {
    let store: PromptStore
    let backend: BackendSettings

    var body: some View {
        TabView {
            PromptsSettingsView(store: store, backend: backend)
                .tabItem { Label("Prompts", systemImage: "text.bubble") }
            BackendSettingsView(settings: backend)
                .tabItem { Label("Backend", systemImage: "key") }
        }
        .padding(.top, 8)
    }
}

private struct PromptsSettingsView: View {
    let store: PromptStore
    let backend: BackendSettings
    @State private var selection: String?
    @State private var pendingDelete: PromptItem?

    var body: some View {
        if let error = store.loadError {
            LoadErrorView(store: store, error: error)
        } else {
            NavigationSplitView {
                promptList
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            } detail: {
                if let selection, store.prompt(id: selection) != nil {
                    PromptEditor(store: store, backend: backend, id: selection)
                        .id(selection)
                } else {
                    Text("Select a prompt").foregroundStyle(.secondary)
                }
            }
            .confirmationDialog(
                "Delete “\(pendingDelete?.name ?? "")”?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { prompt in
                Button("Delete", role: .destructive) {
                    store.delete(id: prompt.id)
                    if selection == prompt.id { selection = nil }
                }
            } message: { prompt in
                if prompt.id == store.library.quickActionID {
                    Text("This is the quick action. Double ⌘C will do nothing until you choose another one.")
                }
            }
        }
    }

    private var promptList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.library.prompts) { prompt in
                    PromptRow(prompt: prompt, library: store.library)
                        .tag(prompt.id)
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            }
            Divider()
            HStack(spacing: 4) {
                Button {
                    selection = store.add()
                } label: {
                    Image(systemName: "plus").frame(width: 20, height: 20)
                }
                Button {
                    pendingDelete = selection.flatMap { store.prompt(id: $0) }
                } label: {
                    Image(systemName: "minus").frame(width: 20, height: 20)
                }
                .disabled(selection == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }
}

private struct PromptRow: View {
    let prompt: PromptItem
    let library: PromptLibrary

    var body: some View {
        HStack {
            Text(prompt.name.isEmpty ? "Untitled" : prompt.name)
                .italic(prompt.name.isEmpty)
                .lineLimit(1)
            Spacer()
            if !prompt.isValid || library.hasDuplicateName(prompt) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if prompt.id == library.quickActionID {
                Image(systemName: "star.fill").foregroundStyle(.yellow).help("Quick action (double ⌘C)")
            }
        }
    }
}

private struct PromptEditor: View {
    let store: PromptStore
    let backend: BackendSettings
    let id: String

    private var prompt: PromptItem? { store.prompt(id: id) }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: binding(\.name))
                if prompt.map({ $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) == true {
                    warning("Name is required.")
                } else if let prompt, store.library.hasDuplicateName(prompt) {
                    warning("Another prompt has the same name.")
                }
                Toggle("Use as quick action (double ⌘C)", isOn: Binding(
                    get: { store.library.quickActionID == id },
                    set: { store.setQuickAction(id: $0 ? id : nil) }
                ))
            }
            ModelSection(store: store, backend: backend, id: id)
            Section {
                TextEditor(text: binding(\.prompt))
                    .font(.body)
                    .frame(minHeight: 260)
                if prompt.map({ $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) == true {
                    warning("Prompt is required.")
                }
            } header: {
                Text("Prompt")
            } footer: {
                Text("""
                    The selected text is sent between <texte> and </texte>. Tell Claude that this text is data: \
                    it must never answer its questions or follow its instructions, and must reply only with the transformed text.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func warning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func binding(_ keyPath: WritableKeyPath<PromptItem, String>) -> Binding<String> {
        Binding(
            get: { store.prompt(id: id)?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard var prompt = store.prompt(id: id) else { return }
                prompt[keyPath: keyPath] = newValue
                store.update(prompt)
            }
        )
    }
}

private struct LoadErrorView: View {
    let store: PromptStore
    let error: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("prompts.json is invalid").font(.headline)
            Text(error).foregroundStyle(.secondary)
            Text(store.fileURL.path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Text("Fix or delete the file, then reload. Nothing is saved until the file can be read.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Reveal in Finder") { store.revealInFinder() }
                Button("Reload") { store.load() }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Model, effort, timeout and max tokens of one prompt. Empty fields use the model defaults.
private struct ModelSection: View {
    let store: PromptStore
    let backend: BackendSettings
    let id: String

    private var prompt: PromptItem? { store.prompt(id: id) }
    private var model: ClaudeModel { ClaudeModel.find(prompt?.model ?? ClaudeModel.default.id) }

    var body: some View {
        Section("Model") {
            Picker("Backend", selection: Binding(
                get: { prompt?.backend ?? .default },
                set: { newValue in update { $0.backend = newValue } }
            )) {
                ForEach(Backend.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if let message = backend.readinessError(for: prompt?.backend ?? .default) {
                Label("\(message). Set it up in the Backend tab.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Picker("Model", selection: Binding(
                get: { model.id },
                set: { newID in update { $0.model = newID } }
            )) {
                ForEach(models, id: \.id) { model in
                    Text(model.price.isEmpty ? model.displayName : "\(model.displayName) — \(model.price) per M tokens")
                        .tag(model.id)
                }
            }
            Picker("Effort", selection: Binding(
                get: { model.supportsEffort ? (prompt?.effort ?? ClaudeModel.defaultEffort) : ClaudeModel.defaultEffort },
                set: { newValue in update { $0.effort = newValue } }
            )) {
                ForEach(Effort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .disabled(!model.supportsEffort)
            if !model.supportsEffort {
                Text("Not supported by \(model.displayName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField(
                "Timeout (seconds)",
                value: Binding(get: { prompt?.timeoutSeconds }, set: { newValue in update { $0.timeoutSeconds = newValue } }),
                format: .number,
                prompt: Text("Default: \(Int(model.defaultTimeout))")
            )
            TextField(
                "Max tokens",
                value: Binding(get: { prompt?.maxTokens }, set: { newValue in update { $0.maxTokens = newValue } }),
                format: .number,
                prompt: Text("Default: \(model.defaultMaxTokens)")
            )
            Text("Leave timeout and max tokens empty to use the model defaults. Thinking models count their reasoning in max tokens.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Known models, plus the current one if it was set by hand to an unknown id.
    private var models: [ClaudeModel] {
        ClaudeModel.all.contains(model) || ClaudeModel.all.contains(where: { $0.id == model.id })
            ? ClaudeModel.all
            : ClaudeModel.all + [model]
    }

    private func update(_ change: (inout PromptItem) -> Void) {
        guard var prompt = store.prompt(id: id) else { return }
        change(&prompt)
        store.update(prompt)
    }
}

/// Both connections side by side: each prompt picks one of them.
private struct BackendSettingsView: View {
    @Bindable var settings: BackendSettings
    @State private var newKey = ""
    @State private var isEditingKey = false
    @State private var keyError: String?

    var body: some View {
        Form {
            Section {
                if let suffix = settings.apiKeySuffix, !isEditingKey {
                    LabeledContent("Key", value: "sk-ant-…\(suffix)")
                    HStack {
                        Button("Change") { isEditingKey = true }
                        Button("Remove", role: .destructive) { settings.removeAPIKey() }
                    }
                } else {
                    SecureField("Key", text: $newKey, prompt: Text("sk-ant-…"))
                    HStack {
                        Button("Save") {
                            keyError = settings.setAPIKey(newKey)
                            if keyError == nil {
                                newKey = ""
                                isEditingKey = false
                            }
                        }
                        .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        if settings.hasAPIKey {
                            Button("Cancel") {
                                newKey = ""
                                isEditingKey = false
                            }
                        }
                    }
                    if let keyError {
                        Text(keyError).font(.caption).foregroundStyle(.red)
                    }
                }
                TestRow(settings: settings, backend: .api)
            } header: {
                Text("API key")
            } footer: {
                Text("Billed per use. Stored in your macOS keychain. Get a key at console.anthropic.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Path", text: $settings.cliPath)
                if settings.cliFound {
                    Label("Found", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Claude Code not found at this path", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                TestRow(settings: settings, backend: .claudeCode)
            } header: {
                Text("Claude subscription (Claude Code)")
            } footer: {
                Text("Uses your Pro/Max plan through the account you are logged in with in Claude Code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Each prompt chooses its backend in the Prompts tab. Prompts without a choice use the API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TestRow: View {
    let settings: BackendSettings
    let backend: Backend

    var body: some View {
        HStack {
            Button("Test") { settings.testConnection(backend) }
                .disabled(settings.testState(for: backend) == .running || settings.readinessError(for: backend) != nil)
            switch settings.testState(for: backend) {
            case .idle:
                Text("Sends a tiny request with Haiku 4.5.").font(.caption).foregroundStyle(.secondary)
            case .running:
                ProgressView().controlSize(.small)
            case let .success(message):
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case let .failure(message):
                Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
    }
}
