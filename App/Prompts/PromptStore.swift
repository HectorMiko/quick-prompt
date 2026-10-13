import AppKit
import Observation
import QuickPromptCore

/// Owns `prompts.json`. Every change is saved immediately.
/// When the file is invalid, nothing is saved so the user's file is never overwritten.
@MainActor @Observable
final class PromptStore {
    static let defaultURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("quick-prompt", isDirectory: true)
        .appendingPathComponent("prompts.json")

    let fileURL: URL
    private(set) var library = PromptLibrary()
    /// Set when `prompts.json` cannot be read. The store is then read-only and empty.
    private(set) var loadError: String?

    @ObservationIgnored var onSaveError: ((String) -> Void)?

    init(fileURL: URL = PromptStore.defaultURL) {
        self.fileURL = fileURL
    }

    func load() {
        do throws(PromptFile.LoadError) {
            if let library = try PromptFile.load(from: fileURL) {
                self.library = library
                Log.prompts.info("Loaded \(library.prompts.count) prompts")
            } else {
                library = DefaultPrompts.makeLibrary()
                Log.prompts.info("No prompts file, created defaults")
                save()
            }
            loadError = nil
        } catch {
            library = PromptLibrary()
            switch error {
            case let .unreadable(message), let .invalid(message):
                loadError = message
            }
            Log.prompts.error("prompts.json invalid: \(self.loadError ?? "", privacy: .public)")
        }
    }

    func prompt(id: String) -> PromptItem? {
        library.prompts.first { $0.id == id }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // MARK: - Mutations

    /// Adds an empty prompt and returns its id.
    func add() -> String? {
        mutate { $0.add().id }
    }

    func update(_ prompt: PromptItem) {
        mutate { $0.update(prompt) }
    }

    func delete(id: String) {
        mutate { $0.delete(id: id) }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        mutate { $0.move(fromOffsets: source, toOffset: destination) }
    }

    func setQuickAction(id: String?) {
        mutate { $0.setQuickAction(id: id) }
    }

    @discardableResult
    private func mutate<T>(_ change: (inout PromptLibrary) -> T) -> T? {
        guard loadError == nil else { return nil }
        let result = change(&library)
        save()
        return result
    }

    private func save() {
        do {
            try PromptFile.save(library, to: fileURL)
        } catch {
            Log.prompts.error("Saving prompts failed: \(error.localizedDescription, privacy: .public)")
            onSaveError?("Could not save prompts")
        }
    }
}
